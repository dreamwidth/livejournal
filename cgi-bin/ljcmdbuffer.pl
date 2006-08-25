#!/usr/bin/perl
#

use strict;
use Class::Autouse qw(LJ::Event);

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
require "$ENV{LJHOME}/cgi-bin/ljmail.pl";

package LJ::Cmdbuffer;

# built-in commands
%LJ::Cmdbuffer::cmds =
    (

     # ping weblogs.com with updates?  takes a $u argument
     weblogscom => {
         too_old => 60*60*2,  # 2 hours old = qbufferd not running?
         once_per_user => 1,
         run => \&LJ::Cmdbuffer::_weblogscom,
     },

     # emails that previously failed to send
     send_mail => {
         arg_format => 'raw',
         too_old => 60*60*24*30, # 30 days is way too old for mail to be relevant
         unordered => 1,         # order irrelevant
         run => \&LJ::Cmdbuffer::_send_mail,
     },

     );

# <LJFUNC>
# name: LJ::Cmdbuffer::flush
# des: flush up to 500 rows of a given command type from the cmdbuffer table
# args: dbh, db, cmd, userid?
# des-dbh: master database handle
# des-db: database cluster master
# des-cmd: a command type registered in %LJ::Cmdbuffer::cmds
# des-userid: optional userid to which flush should be constrained
# returns: 1 on success, 0 on failure
# </LJFUNC>
sub LJ::Cmdbuffer::flush
{
    my ($dbh, $db, $cmd, $userid) = @_;
    return 0 unless $cmd;

    my $mode = "run";
    if ($cmd =~ s/:(\w+)//) {
        $mode = $1;
    }

    my $code = $LJ::Cmdbuffer::cmds{$cmd} ?
        $LJ::Cmdbuffer::cmds{$cmd}->{$mode} : $LJ::HOOKS{"cmdbuf:$cmd:$mode"}->[0];
    return 0 unless $code;

    # start/finish modes
    if ($mode ne "run") {
        $code->($dbh);
        return 1;
    }

    # 0 = never too old
    my $too_old = LJ::Cmdbuffer::get_property($cmd, 'too_old') || 0;

    # 0 == okay to run more than once per user
    my $once_per_user = LJ::Cmdbuffer::get_property($cmd, 'once_per_user') || 0;

    # 'url' = urlencode, 'raw' = don't urlencode
    my $arg_format = LJ::Cmdbuffer::get_property($cmd, 'arg_format') || 'url';

    # 0 == order of the jobs matters, process oldest first
    my $unordered = LJ::Cmdbuffer::get_property($cmd, 'unordered') || 0;

    my $clist;
    my $loop = 1;

    my $where = "cmd=" . $dbh->quote($cmd);
    if ($userid) {
        $where .= " AND journalid=" . $dbh->quote($userid);
    }

    my $orderby;
    unless ($unordered) {
        $orderby = "ORDER BY cbid";
    }

    my $LIMIT = 500;

    while ($loop &&
           ($clist = $db->selectall_arrayref("SELECT cbid, UNIX_TIMESTAMP() - UNIX_TIMESTAMP(instime), journalid ".
                                             "FROM cmdbuffer ".
                                             "WHERE $where $orderby LIMIT $LIMIT")) &&
           $clist && @$clist)
    {
        my @too_old;
        my @cbids;

        # citem: [ cbid, age, journalid ]
        foreach my $citem (@$clist) {
            if ($too_old && $citem->[1] > $too_old) {
                push @too_old, $citem->[0];
            } else {
                push @cbids, $citem->[0];
            }
        }
        if (@too_old) {
            local $" = ",";
            $db->do("DELETE FROM cmdbuffer WHERE cbid IN (@too_old)");
        }

        foreach my $cbid (@cbids) {
            my $got_lock = $db->selectrow_array("SELECT GET_LOCK('cbid-$cbid',10)");
            return 0 unless $got_lock;
            # sadly, we have to do another query here to verify the job hasn't been
            # done by another thread.  (otherwise we could've done it above, instead
            # of just getting the id)

            my $c = $db->selectrow_hashref("SELECT cbid, journalid, cmd, instime, args " .
                                           "FROM cmdbuffer WHERE cbid=?", undef, $cbid);
            next unless $c;

            if ($arg_format eq "url") {
                my $a = {};
                LJ::decode_url_string($c->{'args'}, $a);
                $c->{'args'} = $a;
            }
            # otherwise, arg_format eq "raw"

            # run handler
            $code->($dbh, $db, $c);

            # if this task is to be run once per user, go ahead and delete any jobs
            # for this user of this type and remove them from the queue
            my $wh = "cbid=$cbid";
            if ($once_per_user) {
                $wh = "cmd=" . $db->quote($cmd) . " AND journalid=" . $db->quote($c->{journalid});
                @$clist = grep { $_->[2] != $c->{journalid} } @$clist;
            }

            $db->do("DELETE FROM cmdbuffer WHERE $wh");
            $db->do("SELECT RELEASE_LOCK('cbid-$cbid')");
        }
        $loop = 0 unless scalar(@$clist) == $LIMIT;
    }

    return 1;
}

# <LJFUNC>
# name: LJ::Cmdbuffer::get_property
# des: get a property of an async job type, either built-in or site-specific
# args: cmd, prop
# des-cmd: a registered async job type
# des-prop: the property name to look up
# returns: value of property (whatever it may be) on success, undef on failure
# </LJFUNC>
sub get_property {
    my ($cmd, $prop) = @_;
    return undef unless $cmd && $prop;

    if (my $c = $LJ::Cmdbuffer::cmds{$cmd}) {
        return $c->{$prop};
    }

    if (LJ::are_hooks("cmdbuf:$cmd:$prop")) {
        return LJ::run_hook("cmdbuf:$cmd:$prop");
    }

    return undef;
}

sub _weblogscom {
    # user, title, url
    my ($dbh, $db, $c) = @_;
    my $a = $c->{'args'};
    eval {
        eval "use XMLRPC::Lite;";
        unless ($@) {
            XMLRPC::Lite
                ->new( proxy => "http://rpc.weblogs.com/RPC2",
                       timeout => 5 )
                ->call('weblogUpdates.ping', # xml-rpc method call
                       LJ::ehtml($a->{'title'}) . " \@ $LJ::SITENAMESHORT",
                       $a->{'url'},
                       "$LJ::SITEROOT/misc/weblogs-change.bml?user=$a->{'user'}");
        }
    };

    return 1;
}

sub _send_mail {
    my ($dbh, $db, $c) = @_;

    my $msg = Storable::thaw($c->{'args'});
    return LJ::send_mail($msg, "async");
}

1;

package LJ::Event::NewUserpic;
use strict;
use base 'LJ::Event';
use Class::Autouse qw(LJ::Entry);
use Carp qw(croak);

sub new {
    my ($class, $up) = @_;
    croak "No userpic" unless $up;

    return $class->SUPER::new($up->owner, $up->id);
}

sub as_string {
    my $self = shift;

    return $self->event_journal->display_username . " has uploaded a new userpic.";
}

sub as_html {
    my $self = shift;
    my $up = $self->userpic;
    return "(Deleted userpic)" unless $up && $up->valid;

    return $self->event_journal->ljuser_display . " has uploaded a new <a href='" . $up->url . "'>userpic</a>.";
}

sub as_sms {
    my $self = shift;

    return $self->event_journal->display_username . " has uploaded a new userpic. You can view it at: " .
        $self->userpic->url;
}

sub as_email_string {
    my ($self, $u) = @_;

    my $username = $u->user;
    my $poster = $self->userpic->owner->user;
    my $userpic = $self->userpic->url;
    my $journal_url = $self->userpic->owner->journal_base;
    my $profile = $self->userpic->owner->profile_url;

    my $email = "Hi $username,

$poster has uploaded a new userpic! You can see it at:
   $userpic

You can:

  - View all of $poster\'s userpics:
    $LJ::SITEROOT/allpics.bml?user=$poster";

    unless (LJ::is_friend($u, $self->userpic->owner)) {
        $email .= "
  - Add $poster as a friend:
    $LJ::SITEROOT/friends/add.bml?user=$poster";
    }

$email .= "
  - View their journal:
    $journal_url
  - View their profile:
    $profile";

    return $email;
}


sub as_email_html {
    my ($self, $u) = @_;

    my $username = $u->ljuser_display;
    my $poster = $self->userpic->owner->ljuser_display;
    my $postername = $self->userpic->owner->user;
    my $userpic = $self->userpic->imgtag;
    my $journal_url = $self->userpic->owner->journal_base;
    my $profile = $self->userpic->owner->profile_url;

    my $email = "Hi $username,

$poster has uploaded a new userpic:
<blockquote>$userpic</blockquote>
You can:<ul>";

    $email .= "<li><a href=\"$LJ::SITEROOT/allpics.bml?user=$postername\">View all of $postername\'s userpics</a></li>";
    $email .= "<li><a href=\"$LJ::SITEROOT/friends/add.bml?user=$postername\">Add $postername as a friend</a></li>"
        unless (LJ::is_friend($u, $self->userpic->owner));
    $email .= "<li><a href=\"$journal_url\">View their journal</a></li>";
    $email .= "<li><a href=\"$profile\">View their profile</a></li></ul>";

    return $email;
}

sub userpic {
    my $self = shift;
    my $upid = $self->arg1 or die "No userpic id";
    return eval { LJ::Userpic->new($self->event_journal, $upid) };
}

sub content {
    my $self = shift;
    my $up = $self->userpic;

    return undef unless $up && $up->valid;

    return $up->imgtag;
}

sub as_email_subject {
    my $self = shift;
    return sprintf "%s uploaded a new userpic!", $self->event_journal->display_username;
}

sub zero_journalid_subs_means { "friends" }

sub subscription_as_html {
    my ($class, $subscr) = @_;

    my $journal = $subscr->journal;

    return "One of my friends uploads a new userpic" unless $journal;

    my $ljuser = $subscr->journal->ljuser_display;
    return "$ljuser uploads a new userpic";
}

# only users with the track_user_newuserpic cap can use this
sub available_for_user  {
    my ($class, $u, $subscr) = @_;

    return 0 if ! $u->get_cap('track_user_newuserpic') &&
        $subscr->journalid;

    return 1;
}

1;

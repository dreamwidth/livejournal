package LJ::Setting::Language;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_community ? 0 : 1;
}

sub helpurl {
    my ($class, $u) = @_;

    return "change_language";
}

sub label {
    my $class = shift;

    return $class->ml('setting.language.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $lang = $class->get_arg($args, "lang") || BML::get_language();
    my $lang_list = LJ::Lang::get_lang_names();

    my $ret = LJ::html_select({
        name => "${key}lang",
        selected => $lang,
    }, @$lang_list);

    my $errdiv = $class->errdiv($errs, "lang");
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "lang");

    $class->errors( lang => $class->ml('setting.language.error.invalid') )
        unless $val && grep { $val eq $_ } @{LJ::Lang::get_lang_names()};

    return 1;
}

sub save {
    my ($class, $u, $args) = @_;
    $class->error_check($u, $args);

    my $val = $class->get_arg($args, "lang");
    LJ::set_remote_language($val);

    return 1;
}

1;

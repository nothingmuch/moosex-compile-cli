#!/usr/bin/perl

package MooseX::Compile::CLI::Command::clean;
use Moose;

extends qw(Moose::Object MooseX::App::Cmd::Command);

with qw(MooseX::Getopt);

use Path::Class;
use MooseX::Types::Path::Class;
use MooseX::AttributeHelpers;
use Prompt::ReadKey;

has force => (
    doc => "Remove without asking.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has verbose => (
    doc => "List files as they're being deleted.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has clean_includes => (
    doc => "The dirs argument implicitly gets all the includes classes would be normally searched in.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has perl_inc => (
    doc => "Whether or not to use \@INC for the default list of includes to search.",
    isa => "Bool",
    is  => "rw",
    default => 1,
);

has local_lib => (
    doc => "Like specifying `-I lib`",
    cmd_aliases => "l",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has local_test_lib => (
    doc => "Like specifying `-I t/lib`",
    cmd_aliases => "t",
    isa => "Bool",
    is  => "rw",
    default => 0,
);


has inc => (
    doc => "Specify additional include paths for classes.",
    cmd_aliases => "I",
    metaclass => "Collection::Array",
    isa => "ArrayRef",
    is  => "rw",
    auto_deref => 1,
    coerce     => 1,
    default    => sub { [] },
    provides   => {
        push => "add_to_inc",
    },
);

has dirs => (
    doc => "Specify directories to scan for compiled modules recursively.",
    metaclass => "Collection::Array",
    isa => "ArrayRef",
    is  => "rw",
    auto_deref => 1,
    coerce     => 1,
    default    => sub { [] },
    provides   => {
        push => "add_to_dirs",
    },
);

has classes => (
    doc => "Specific classes to clean",
    metaclass => "Collection::Array",
    isa => "ArrayRef[Str]",
    is  => "rw",
    auto_deref => 1,
    coerce     => 1,
    default    => sub { [] },
    provides   => {
        push => "add_to_classes",
    },
);

sub run {
    my ( $self, $opts, $args ) = @_;

    $self->build_from_opts( $opts, $args );

    $self->clean_all_files;
}

sub clean_all_files {
    my $self = shift;

    $self->clean_files( $self->all_files );
}

sub clean_files {
    my ( $self, @files ) = @_;

    my @delete = $self->should_delete(@files);

    $self->delete_file($_) for @delete;
}

sub should_delete {
    my ( $self, @files ) = @_;

    return @files if $self->force;

    my @ret;

    my @file_list = @files;

    my $file; # shared by while loop and these closures

    my %options = (
        yes        => sub { push @ret, $file },
        rest       => sub { die [ @ret, $file, @file_list ] },
        everything => sub { die \@files },
        none       => sub { die \@ret },
        quit       => sub { die [] },
        no         => sub { },
    );

    while ( $file = shift @file_list ) {
        my $opt = $self->prompt_for_delete($file);

        my $cb = $options{$opt} || die "Unknown option from prompt: $opt";

        local $@;
        eval { $cb->() };
        return @{$@} if ref $@; # short circuiting

        die $@ if $@;
    }

    return @ret;
}

sub prompt_for_delete {
    my ( $self, $file ) = @_;

    my $name = $file->{rel};
    $name =~ s/\.pmc$/.{pmc,mopc}/;

    Prompt::ReadKey->new->prompt(
        prompt  => "Clean up class '$file->{class}' ($name in $file->{dir})?",
        options => [
            {
                name    => "yes",
                doc     => "delete this file and the associated .mopc file",
            },
            {
                name    => "no",
                doc     => "don't delete this file",
                default => 1,
            },
            {
                name => "rest",
                doc  => "delete all remaining files",
                key  => 'a',
            },
            {
                name => "everything",
                doc  => "delete all files, including ones previously marked 'no'",
            },
            {
                name => "none",
                key  => "d",
                doc  => "don't delete any more files, but do delete the ones specified so far",
            },
            {
                name => "quit",
                doc  => "exit, without deleting any files",
            },
        ],
    );
}

sub delete_file {
    my ( $self, $file ) = @_;

    foreach my $file ( @{ $file }{qw(file mopc)} ) {
        warn "Deleting $file\n" if $self->verbose;
        $file->remove or die "couldn't unlink $file: $!";
    }
}

sub pmc_to_mopc {
    my ( $self, $pmc_file ) = @_;

    my $pmc_basename = $pmc_file->basename;

    ( my $mopc_basename = $pmc_basename ) =~ s/\.pmc$/.mopc/ or return;

    my $mopc_file = $pmc_file->parent->file($mopc_basename);

    return $mopc_file if -f $mopc_file;

    return;
}

sub new_match {
    my ( $self, %args ) = @_;

    my $dir = $args{dir} || die "dir is required";

    my $file = $args{file} ||= ($args{rel} || die "either 'file' or 'rel' is required")->absolute($dir);
    -f $file or die "file '$file' does not exist";

    my $rel = $args{rel} ||= $args{file}->relative($dir);
    $rel->is_absolute and die "rel is not relative";

    $args{mopc} = $self->pmc_to_mopc($file) or return;

    $args{class} ||= do {
        my $basename = $rel->basename;
        $basename =~ s/\.pmc$//;

        $rel->dir->cleanup eq dir()
            ? $basename
            : join( "::", $rel->dir->dir_list, $basename );
    };

    return \%args;
}

sub all_files {
    my $self = shift;

    return (
        $self->files_from_dirs( $self->dirs ),
        $self->files_from_classes( $self->classes ),
    );
}

sub files_from_dirs {
    my ( $self, @dirs ) = @_;
    return unless @dirs;

    my @files;

    foreach my $dir ( @dirs ) {
        $dir->recurse(
            callback => sub {
                my $file = shift;
                push @files, $self->new_match( file => $file, dir => $dir ) if !$file->is_dir and $self->filter_file($file);
            },
        );
    }

    return @files;
}

sub filter_file {
    my ( $self, $file ) = @_;

    return $file if $file->basename =~ m/\.pmc$/ and -f $file;

    return;
}

sub files_from_classes {
    my ( $self, @classes ) = @_;

    my @filenames = map {
        my $file = "$_.pmc";
        $file =~ s{::}{/}g;
        $file;
    } @classes;

    $self->files_in_includes(@filenames);
}

sub files_in_includes {
    my ( $self, @files ) = @_;

    map { $self->file_in_includes($_) } @files;
}

sub file_in_includes {
    my ( $self, $file ) = @_;

    map { $self->new_match( rel => $file, dir => $_ ) } grep { $_->filter_file( $_->file($file) ) } $self->includes;
}

sub build_from_opts {
    my ( $self, $opts, $args ) = @_;

    foreach my $arg ( @$args ) {
        if ( -d $arg ) {
            $self->add_to_dirs($arg);
        } else {
            $self->add_to_classes($arg);
        }
    }

    $self->add_to_inc( dir("lib") ) if $self->local_lib;
    $self->add_to_inc( dir(qw(t lib)) ) if $self->local_test_lib;

    $self->add_to_inc( @INC ) if $self->perl_inc;

    $self->add_to_dirs( $self->inc ) if $self->clean_includes;

    $_ = dir($_) for @{ $self->dirs }, @{ $self->inc };

    @$args = ();

    return;
}


__PACKAGE__

__END__

=pod

=head1 NAME

MooseX::Compile::CLI::Command::clean - 

=head1 SYNOPSIS

	use MooseX::Compile::CLI::Command::clean;

=head1 DESCRIPTION

=cut



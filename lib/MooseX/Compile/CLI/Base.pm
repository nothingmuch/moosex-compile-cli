#!/usr/bin/perl

use MooseX::Compile ();

package MooseX::Compile::CLI::Base;
use Moose;

extends qw(MooseX::App::Cmd::Command);

with qw(MooseX::Getopt);

use Path::Class;
use MooseX::AttributeHelpers;
use MooseX::Types::Path::Class;

has verbose => (
    doc => "Print additional information while running.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has force => (
    doc => "Process without asking.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has dirs => (
    doc => "Directories to process recursively.",
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
    doc => "Specific classes to process in 'inc'",
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


has perl_inc => (
    doc => "Whether or not to use \@INC for the default list of includes to search.",
    isa => "Bool",
    is  => "rw",
    default => 1,
);

has local_lib => (
    doc => "Like specifying '-I lib'",
    cmd_aliases => "l",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has local_test_lib => (
    doc => "Like specifying '-I t/lib'",
    cmd_aliases => "t",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has inc => (
    doc => "Library include paths in which specified classes are searched.",
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

sub file_in_dir {
    die "abstract method";
}

sub class_to_filename {
    die "abstract method";
}

sub filter_file {
    die "abstract method";
}

sub run {
    my ( $self, $opts, $args ) = @_;

    $self->build_from_opts( $opts, $args );

    inner();
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

    @$args = ();

    $self->add_to_inc( dir("lib") ) if $self->local_lib;
    $self->add_to_inc( dir(qw(t lib)) ) if $self->local_test_lib;

    $self->add_to_inc( @INC ) if $self->perl_inc;

    inner();

    $_ = dir($_) for @{ $self->dirs }, @{ $self->inc };
};

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
                push @files, $self->file_in_dir( file => $file, dir => $dir ) if !$file->is_dir and $self->filter_file($file);
            },
        );
    }

    return @files;
}

sub files_from_classes {
    my ( $self, @classes ) = @_;

    my @files = map { { class => $_, rel => file($self->class_to_filename($_)) }  } @classes;

    $self->files_in_includes(@files);
}

sub files_in_includes {
    my ( $self, @files ) = @_;

    map { $self->file_in_includes($_) } @files;
}

sub file_in_includes {
    my ( $self, $file ) = @_;

    my @matches = grep { $self->filter_file( $_->file($file->{rel}) ) } $self->inc;

    die "No file found for $file->{class}\n" unless @matches;

    map { $self->file_in_dir( %$file, dir => $_ ) } @matches;
}


__PACKAGE__

__END__


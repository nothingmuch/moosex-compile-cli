#!/usr/bin/perl

package MooseX::Compile::CLI::Base;
use Moose;

extends qw(MooseX::App::Cmd::Command);

use Path::Class;
use MooseX::AttributeHelpers;
use MooseX::Types::Path::Class;

has verbose => (
    documentation => "Print additional information while running.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has force => (
    documentation => "Process without asking.",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has dirs => (
    documentation => "Directories to process recursively.",
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
    documentation => "Specific classes to process in 'inc'",
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
    documentation => "Whether or not to use \@INC for the default list of includes to search.",
    isa => "Bool",
    is  => "rw",
    default => 1,
);

has local_lib => (
    documentation => "Like specifying '-I lib'",
    cmd_aliases => "l",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has local_test_lib => (
    documentation => "Like specifying '-I t/lib'",
    cmd_aliases => "t",
    isa => "Bool",
    is  => "rw",
    default => 0,
);

has inc => (
    documentation => "Library include paths in which specified classes are searched.",
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
    my ( $self, %args ) = @_;

    my $dir = $args{dir} || die "dir is required";

    my $file = $args{file} ||= ($args{rel} || die "either 'file' or 'rel' is required")->absolute($dir);
    -f $file or die "file '$file' does not exist";

    my $rel = $args{rel} ||= $args{file}->relative($dir);
    $rel->is_absolute and die "rel is not relative";

    $args{class} ||= do {
        my $basename = $rel->basename;
        $basename =~ s/\.(?:pmc?|mopc)$//;

        $rel->dir->cleanup eq dir()
            ? $basename
            : join( "::", $rel->dir->dir_list, $basename );
    };

    return \%args;
}

sub filter_file {
    die "abstract method";
}

sub class_to_filename {
    my ( $self, $class ) = @_;

    ( my $file = "$class.pm" ) =~ s{::}{/}g;

    return $file;
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


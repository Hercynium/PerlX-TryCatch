#!/usr/bin/env perl
use strict;
use warnings;
use feature ':5.10.1';

package Try::Harder;
use Carp;
use Try::Tiny ();

sub _run_with_context {
  my $wantarray = shift;
  my $code      = shift;

  croak __PACKAGE__ . "::_run_with_context *must* be run in list context"
    unless wantarray;

  if ( $wantarray ) {
    return $code->( @_ );
  }

  if ( defined $wantarray ) {
    return scalar $code->( @_ );
  }

  $code->( @_ ); # void context
  return;
}

package Try::Harder::EndOfBlock;

package main;

use Data::Dumper;

sub try () {};


=for example

Transform this:

  try {
    my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
    print "inside a try block. context is [$wax]\n";
    die "exception thrown in try and caught in catch\n" if $throw_exception;
    my $retval = "returned from a try block";
    (wantarray ? return split / /, $retval : return $retval) if $return_from_trycatch;
    my $foo = "fell off the end of a try block";
  }
  catch {
    chomp(my $retval = $_);
    my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
    print "inside a catch block. context is [$wax]\n";
    (wantarray ? return split / /, $retval : return $retval) if $return_from_trycatch;
    my $foo = "fell off the end of a catch block";
  }

Into this:

=cut


sub foo {
  my ($return_from_trycatch, $throw_exception) = @_;

  # begin transformed code
  try;
  do {
    local $Try::Harder::_wantarray = wantarray;

    local @Try::Harder::_retval =
      Try::Tiny::try {
        return Try::Harder::_run_with_context(
          $Try::Harder::_wantarray,
          sub {
            # this was the original "try" block. note that it is now
            # wrapped in a "do" block, but otherwise unchanged.
            local @Try::Harder::_lastval = do {
              my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
              print "inside a try block. context is [$wax]\n";
              die "exception thrown in try and caught in catch\n" if $throw_exception;
              my $retval = "returned from a try block";
              (wantarray ? return split / /, $retval : return $retval) if $return_from_trycatch;
              # this value is useless but we capture it anyway, just because.
              my $foo = "fell off the end of a try block";
            };
            bless [@Try::Harder::_lastval], "Try::Harder::EndOfBlock";
          }
        );
      }

      Try::Tiny::catch {
        return Try::Harder::_run_with_context(
          $Try::Harder::_wantarray,
          sub {
            # this was the original "catch" block:
            local @Try::Harder::_lastval = do {
              chomp(my $retval = $_);
              my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
              print "inside a catch block. context is [$wax]\n";
              (wantarray ? return split / /, $retval : return $retval) if $return_from_trycatch;
              # this value is useless but we capture it anyway, just because.
              my $foo = "fell off the end of a catch block";
            };
            bless [@Try::Harder::_lastval], "Try::Harder::EndOfBlock";
          }
        );
      }

    ;

    ($Try::Harder::_wantarray ? return @Try::Harder::_retval : return $Try::Harder::_retval[0])
      unless ref($Try::Harder::_retval[0]) eq "Try::Harder::EndOfBlock";
  };
  # end transformed code

  my $retval = "fell off the end of a try or catch block";
  wantarray ? return split / /, $retval : return $retval;
}


print Dumper [ scalar foo(1,0) ];
print Dumper [        foo(1,0) ];
print Dumper [ scalar foo(0,0) ];
print Dumper [        foo(0,0) ];
print Dumper [ scalar foo(1,1) ];
print Dumper [        foo(1,1) ];
print Dumper [ scalar foo(0,1) ];
print Dumper [        foo(0,1) ];


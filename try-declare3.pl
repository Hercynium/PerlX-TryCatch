#!/usr/bin/env perl
use strict;
use warnings;
use feature ':5.10.1';

package Try::Harder;
use Carp;

sub _run_with_wantarray {
  my $wantarray = shift;
  my $code      = shift;

  croak __PACKAGE__ . "::_run_with_wantarray *must* be run in list context"
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


#
# starting with this:
#
# try {
#   my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
#   print "inside try block with return. context is [$wax]\n";
#   my $retval = "value from returing from try block";
#   (wantarray ? return split '', $retval : return $retval) if $return_from_try;
#   my $foo = "value from falling off the end of a try block";
# }
#
# end up with this:


sub foo {
  my ($return_from_try) = @_;

  try;
  do {
    local $Try::Harder::_wantarray = wantarray;
    #my $wa = $Try::Harder::_wantarray   ? "list"
    #  : defined $Try::Harder::_wantarray ? "scalar"
    #  : "void";
    #print "WANTARRAY: [$wa]\n";
    local @Try::Harder::_retval = Try::Harder::_run_with_wantarray(
      $Try::Harder::_wantarray,
      sub {
        ; eval {
            # this was the original "try" block. note that it is now
            # wrapped in a "do" block, but otherwise unchanged.
          ; local @Try::Harder::_lastval = do {
            my $wax = wantarray; $wax = $wax ? "list" : defined $wax ? "scalar" : "void";
            print "inside try block with return. context is [$wax]\n";
            my $retval = "value from returing from try block";
            (wantarray ? return split / /, $retval : return $retval) if $return_from_try;
            # this value is useless but we capture it anyway, just because.
            my $foo = "value from falling off the end of a try block";
          }
          ; bless [@Try::Harder::_lastval], "Try::Harder::EndOfBlock";
        };
      }
    );
    #print Dumper \@Try::Harder::_retval;
    ($Try::Harder::_wantarray ? return @Try::Harder::_retval : return $Try::Harder::_retval[0])
      unless ref($Try::Harder::_retval[0]) eq "Try::Harder::EndOfBlock";
  };
  my $retval = "you should only see this if you fell off the end of the try-block";
  wantarray ? return split / /, $retval : return $retval;
}


print Dumper [ scalar foo()  ];
print Dumper [        foo()  ];
print Dumper [ scalar foo(1) ];
print Dumper [        foo(1) ];


#!/usr/bin/env perl
package Try::Declare;
# ABSTRACT try-catch-finally where 'return' actually returns from the sub
use strict;
use warnings;
use Carp; 
use Devel::Declare;
use base qw/Devel::Declare::Context::Simple/;


# declaring a namespace for the object that gets returned when the inner do-block
# ends because the end of the block was reached rather than being exited because
# of an explicit use of "return". I know it's not necessary, but it seems like
# The Right Thing To Do (tm)
BEGIN {
  package
    Try::Declare::EndOfBlock;
}

use vars '$PKG';
$PKG = __PACKAGE__;

# These will hold different types of return values from the
# generated eval & do block. Also not necessary, same rationale.
#our (@_retval, @_lastval, $_wantarray, $_passthru_sub);



sub import {
  my $class  = shift;
  my $caller = caller;
 
  # install a 'try' sub into the caller's namespace
  {
    no strict 'refs';
    *{$caller.'::try'} = sub (&) {};
  }

  # then hook that sub with our transform sub
  Devel::Declare->setup_for(
      $caller,
      { try => { const => \&transform_try } }
  );

}


sub _passthru_sub;

sub transform_try {

  my $ctx = +__PACKAGE__->new->init(@_);

  # report errors from line of 'try {' in user source.
  local $Carp::Internal{'Devel::Declare'} = 1;

  # turn the try sub we're transforming into a no-op with
  # no arguments, since that's how it will be used shortly...
  $ctx->shadow(sub () { } );


  $ctx->skip_declarator
    or croak "Could not parse try block";

  my $linestr = $ctx->get_linestr;
  return unless defined $linestr;

  ### modify the initial "call" to try()...


  #local *{Try::Declare::_passthru_sub} = (
  #    $Try::Declare::_wantarray         ? sub ( @ ) { @_ } :
  #    defined $Try::Declare::_wantarray ? sub ( $ ) { @_ } :
  #    sub () { @_ }
  #);
  #print "PROTO: ", prototype( 'Try::Declare::_passthru_sub' ), "\n";

  # basically, it works like this...
  #  1. Since the try has been converted into a dummy-sub, terminate that
  #     statement so perl doesn't get confused with that follows...
  #  1. enclose the bare-block (which would have been an anonymous sub)
  #     after the "try" into a do-block, so try can return whatever value
  #     the "do" might yeild.
  #  2. Localise the var that will get the value of whatever gets returned
  #     in the original block - only if "return" is invoked.
  #  4. Start a block-eval, with its return value stored in retval...
  my $newcode1 = <<'END_CODE';
; do {
  local $Try::Declare::_wantarray = wantarray;
  print "WANTARRAY? [@{[$Try::Declare::_wantarray // 'undef']}]\n";
  local *Try::Declare::_passthru_sub =
    $Try::Declare::_wantarray         ? sub ( @ ) { @_ } :
    defined $Try::Declare::_wantarray ? sub ( $ ) { @_ } :
    sub () { @_ };
  print "PROTO: ", prototype( 'Try::Declare::_passthru_sub' ), "\n";
  local $Try::Declare::_retval = eval q{ Try::Declare::_passthru_sub eval
END_CODE
  $newcode1 =~ s/\n//msg;
  $newcode1 =~ s/\s+/ /msg;

#print "Splicing in code: [$newcode1]\n";

  substr( $linestr, $ctx->offset, 0 ) = $newcode1;
  $ctx->set_linestr( $linestr );

  # adjust the offset for the stuff we just spliced in
  $ctx->inc_offset( length $newcode1 );

  ### OK, now things start to get weird...

  #my $x = 0;
  #while ( my @inf = caller $x++ ) {
  #  print "caller info: $x => [", join(", ", @inf), "\n";
  #}

  # I'll explain this when I'm sober.
  my $newcode2 =
    # start a "do" block at the top of the eval block
    '; do {' .
    # add code to inject the following right after the closing brace of the "do" block:
    $ctx->scope_injector_call(
      # terminate the do-block, then return an EndOfBlock object from the "eval" block:
      '; bless [], "Try::Declare::EndOfBlock" }; };' .
      # if the eval did not yeild an EndOfBlock object, then it was exited via a "return"
      # somewhere in the "do" block. Return the apropriate value for the current value
      # of _wantarray.
      '($Try::Declare::_wantarray ? return @Try::Declare::_retval : return $Try::Declare::_retval[0]) unless ref($Try::Declare::_retval) eq "Try::Declare::EndOfBlock"' .
      # finally, close off the outermost "do" block.
      '};'
    )
  ;

  #print "Injecting: [$newcode2]\n";
  $ctx->inject_if_block( $newcode2 )
    or croak "Could not find a code block after try";

}



#######################################################################




package Try::Declare::Test;
use strict;
use warnings;
use Data::Dumper;
BEGIN {
  Try::Declare->import;
}

sub wibble {
  my $foo;
  $_ = "topic/wibble";
  my $mwa = wantarray; $mwa = $mwa ? "list" : defined $mwa ? "scalar" : "void";
  print "wibble: \$_: [$_] wantarray: [$mwa]\n";
  print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";

  try {
    my $wa = wantarray; $wa = $wa ? "list" : defined $wa ? "scalar" : "void";
    print "wibble: try block with return. \$_: [$_] wantarray: [$wa]\n";
    print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";
    return ("try with return in wibble", 1, 2, 3, 4);
    $foo = "something went horribly wrong in try with return";
  }
  return "try with return failed in wibble";
}

sub main {

  my $foo;
  $_ = "topic/main";


  my $mwa = wantarray; $mwa = $mwa ? "list" : defined $mwa ? "scalar" : "void";
  print "main: \$_: [$_] wantarray: [$mwa]\n";
  print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";

  eval {
    my $wa = wantarray; $wa = $wa ? "list" : defined $wa ? "scalar" : "void";
    print "main: normal eval, no return. \$_: [$_] wantarray: [$wa]\n";
    print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";
    $foo = "eval";
  };

  try {
    my $wa = wantarray; $wa = $wa ? "list" : defined $wa ? "scalar" : "void";
    print "main: try block no return. \$_: [$_] wantarray: [$wa]\n";
    print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";
    $foo = "try no return"
  }

  my @wib = wibble;
  print "Wibble returned: ", Dumper \@wib;

  try {
    my $wa = wantarray; $wa = $wa ? "list" : defined $wa ? "scalar" : "void";
    print "main: try block with return. \$_: [$_] wantarray: [$wa]\n";
    print "  caller info: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";
    return "try with return";
    $foo = "something went horribly wrong in try with return";
  }
  return $foo;
}

my $val = main();
print "final: Returned value: ", Dumper $val;
1;

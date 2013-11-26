#!/usr/bin/env perl
package Try::Declare;

use strict;
use warnings;
use Carp; 
use Devel::Declare;
use base qw/Devel::Declare::Context::Simple/;

# These will hold different types of return values from
# the generated eval & do blocks
our ($_retval, $_lastval);

sub import {
  my $class  = shift;
  my $caller = caller;
 
  # install a dummy sub into the caller's namespace
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

# fake namespace for the object that gets returned when the inner do-block ended
# because the end of the block was reached rather than an explicit return.
BEGIN {
  package
    Try::Declare::EndOfBlock;
}


### Some code and comments lovingly stolen from TryCatch.

sub transform_try {

  #my $ctx = Devel::Declare::Context::Simple->new->init(@_);
  my $ctx = +__PACKAGE__->new->init(@_);

  # report errors from line of 'try {' in user source.
  local $Carp::Internal{'Devel::Declare'} = 1;

  # Replace try to be a no-op sub with no args, because that's what it will be
  # once we're done with this.
  $ctx->shadow(sub () { } );

  $ctx->skip_declarator
    or croak "Could not parse try block";

  my $linestr = $ctx->get_linestr;
  return unless defined $linestr;

  ### modify the initial "call" to try()...

  # basically, it works like this...
  #  1. terminate the statement immediately after the "call" to 'try'.
  #  2. Begin a new lexical scope
  #  3. Localise the vars intended for catching:
  #     a. a returned value from the inner-block
  #     b. the value of the last expression in the inner block
  #  4. Start a block-eval, with its return value stored in retval...
  my $newcode1 = '; { local $Try::Declare::_lastval; local $Try::Declare::_retval = eval';
  substr( $linestr, $ctx->offset, 0 ) = $newcode1;
  $ctx->set_linestr( $linestr );

  # adjust the offset for the stuff we just spliced in
  $ctx->inc_offset( length $newcode1 );

  ### OK, now things start to get weird...

  # I'll explain this when I'm sober.
  my $newcode2 =
    '; $Try::Declare::_lastval = do {' .
    $ctx->scope_injector_call(
      #'; print "Out of do block\n"' .
      '; bless [$Try::Declare::_lastval], "Try::Declare::EndOfBlock" };' .
      #'print "Out of eval block\n";' .
### TODO: use Scope::Upper to return from the sub or eval the try block was in, but only
###       when return was *used*. (ref $Try::Declare::_retval ne "Try::Declare::EndOfBlock")
      #'(( blessed $Try::Declare::_retval || "" ) eq "Try::Declare::EndOfBlock") ? ' .
      'ref($Try::Declare::_retval) eq "Try::Declare::EndOfBlock" ? ' .
      'print "no return, last val from block: [$Try::Declare::_lastval]\n" : ' .
      'print "returned: [@{[$Try::Declare::_retval || q||]}]\n" ' .
      ';};'
    );

  #print "Injecting: [$newcode]\n";
  $ctx->inject_if_block( $newcode2 )
    or croak "Could not find a code block after try";

}

#######################################################################




package Try::Declare::Test;
use strict;
use warnings;
BEGIN {
  Try::Declare->import;
}

eval { print "normal eval: [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n" };
$_ = "foo";
try {
  print "$_ calling return from [" . join(",", map { defined $_ ? $_ : "" } caller 0) . "]\n";
  return 5;
  6
}


try { print "not calling return\n" }

1;

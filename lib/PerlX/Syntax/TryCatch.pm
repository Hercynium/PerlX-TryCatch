package PerlX::Syntax::TryCatch;

# ABSTRACT try-catch-finally where 'return' actually returns from the sub

use strict;
use warnings;
use Carp           qw/ carp croak cluck confess /;
use Try::Tiny      ();
use Devel::Declare ();

# TODO: see if 'parent' is already a dep of Devel::Declare
use base qw/ Devel::Declare::Context::Simple /;


use Data::Dumper;

# makes it easier to interpolate package names into generated code strings.
use vars qw/ $PST_PKG $EOB_PKG /;
BEGIN {
  $PST_PKG = __PACKAGE__;
  $EOB_PKG = "${PST_PKG}::EndOfBlockVal";
}

# declaring a namespace for the object that gets returned when the inner do-block
# ends because the end of the block was reached rather than being exited because
# of an explicit use of "return". I know it's not necessary, but it seems like
# The Right Thing To Do (tm)
BEGIN {
  eval "package $EOB_PKG";
}

# Also not necessary to declare these, but same rationale.
use vars qw/ @_RETVAL @_EOBVAL $_WANTARRAY /;

# report errors from these packages from the user's code
$Carp::Internal{ $_ } = 1 for qw/ Devel::Declare Devel::Declare::Context::Simple /;


# TODO: setup imports for catch and finally
sub import {
  my $class  = shift;
  my $caller = caller;

  # install a 'try' sub into the caller's namespace
  {
    no strict 'refs';
    *{"${caller}::try"} = sub (&) {};
    *{"${PST_PKG}::tt_$_"} = \&{"Try::Tiny::$_"} for qw/ try catch finally /;
  }

  # then hook that sub with our transform sub
  Devel::Declare->setup_for(
      $caller,
      { try => { const => \&_transform_try } }
  );

}


# Given the value returned by "wantarray" (true, false, or undef), and a code
# ref, run the code ref with the context indicated by the wantarray value.
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


# For better read/maintainability, I will format injected code nicely, but
# Devel::Declare needs it all in one line. Use this sub to "unformat" it.
sub _unformat_code {
  my ($code) = map {
    s/#[^\n]*//msg; # remove comments
    s/\n//msg;      # remove newlines
    s/\s+/ /msg;    # collapse whitespace
    $_;
  } join ' ', @_;
  return $code;
}

sub _transform_try {

  my $ctx = "$PST_PKG"->new->init( @_ );

  # turn the try sub we're transforming into a no-op with
  # no arguments, since that's how it will be used shortly...
  $ctx->shadow( sub () { } );

  $ctx->skip_declarator
    or croak "Could not parse try block";

  my $linestr = $ctx->get_linestr;
  return unless defined $linestr;  # Maybe this should be an error?

  ### modify the initial "call" to try()...


  # inject this code after the "try" and before the "{"
  my $pre_try_code = _unformat_code <<"END_CODE";
  ; # terminate the call to "try"
  # begin a "do" block to constrain scope
  do {

    # capture the current sub's return context
    local \$${PST_PKG}::_WANTARRAY = wantarray;

    # localise these to catch various values we will use later...
    local \@${PST_PKG}::_RETVAL;
    local \@${PST_PKG}::_EOBVAL;

    # call TT's try, catching the return value in _retval. Note that
    # we're starting a new anonymous sub here, to pass to TT::try
    \@${PST_PKG}::_RETVAL =
      ${PST_PKG}::tt_try {

        # wrap the original try-block in a new anon sub to pass to
        # _run_with_context, which does what it says on the tin...
        return ${PST_PKG}::_run_with_context(
          \$${PST_PKG}::_WANTARRAY,
          sub # the opening brace of the original try block will be right here.
END_CODE

  #print "Injecting Before Try Block: [$pre_try_code]\n";

  substr( $linestr, $ctx->offset, 0 ) = $pre_try_code;
  $ctx->set_linestr( $linestr );

  # adjust the offset for the stuff we just spliced in
  $ctx->inc_offset( length $pre_try_code );


  # this code will get injected *after* the end of the try block
  my $post_try_code = _unformat_code <<"END_CODE";
            # terminate the inner-most "do" block that will
            # wrap the original try block's code
            ;

            # if "return" was not used in the original code, we will end up
            # here. return this object as a sentinel to indicate what happened.
            \$${PST_PKG}::_EOBVAL[0] = bless [\@${PST_PKG}::_EOBVAL], "$EOB_PKG";

          } # end of sub passed to _run_with_context
        );  # end of call to _run_with_context
      }     # end of sub passed to Try::Tiny::try
END_CODE

  # TODO: detect the use of "catch" and/or "finally"
  my $post_post_try_code = _unformat_code <<"END_CODE";
    # terminate the last block in our try-catch-finally construct
    ;

    # we're back in the outer-most do-block, in the original sub. If return was
    # used in any of the try-catch blocks, return the value we captured from here,
    # using the correct context.
    (\$${PST_PKG}::_WANTARRAY ? return \@${PST_PKG}::_RETVAL : return \$${PST_PKG}::_RETVAL[0])
      if ref(\$${PST_PKG}::_EOBVAL[0]) ne "$EOB_PKG";

  }; # terminate the final, outer-most do block.
END_CODE

  ### Here's where things get realy funky. I'll explain it when I'm sober.

  # inject this code after the "{" at the top of the original "try" block
  my $in_try_code = _unformat_code(
    # start a "do" block at the top of the eval block
    "; \@${PST_PKG}::_EOBVAL = do {" .
    # add code to inject the following right after the closing brace of the "do" block:
    $ctx->scope_injector_call( $post_try_code . $post_post_try_code )
  );

  #print "Injecting Into Try Block: [$in_try_code]\n";

  $ctx->inject_if_block( $in_try_code )
    or croak "Could not find a code block after try";

}


1 && q{ I'm a very, very bad man. }; # truth
__END__

#!/bin/sh

perl \
  -Ilib \
  -MPerlX::Syntax::TryCatch \
  -e '
    print sub { try { return "OK" }; return "NOT OK" }->(), "\n"
  '


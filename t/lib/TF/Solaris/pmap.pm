#
# TF means "TestsFor"
#
package TF::Solaris::pmap;

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';

sub test_startup {
  my ($test) = shift;

  if ( ! -x q{/bin/uname} or ($^O ne "solaris")) {
    $test->test_skip("These tests only valid on Solaris");
  }

  $test->next::method;

  # Log::Log4perl Configuration in a string ...
  my $conf = q(
    #log4perl.rootLogger          = DEBUG, Logfile, Screen
    log4perl.rootLogger          = DEBUG, Screen

    #log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    #log4perl.appender.Logfile.filename = test.log
    #log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    #log4perl.appender.Logfile.layout.ConversionPattern = [%r] %F %L %m%n

    log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr  = 0
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
  );

  # ... passed as a reference to init()
  Log::Log4perl::init( \$conf );
}

sub test_constructor {
  my ($test) = shift;

  my $obj = $test->class_name->new(pid => $$);

  isa_ok($obj, $test->class_name, 'Should create new object');

  eq_or_diff($obj->pid, $$, 'PID should match');

  # TODO: Pass bogus PID
  #       Ensure dynamic_symtab returns a value
  #
  my $dsymtab = $obj->dynamic_symtab;
}


1;

#
# TF means "TestsFor"
#
package TF::Solaris::pmap;

use Path::Class::File ();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';

sub test_startup {
  my ($test) = shift;

  if ( ! -x q{/bin/uname} or ($^O ne "solaris")) {
    $test->test_skip("These tests only run on Solaris");
  }
  my @uname_cmd = qw(/bin/uname -r);
  my ($osrev) = qx{@uname_cmd}; chomp($osrev);
  my ($osrev_maj,$osrev_min);
  ($osrev_maj,$osrev_min) = $osrev =~ m{^([\d]+)\.([\d]+)$};
  unless ($osrev_maj == 5 && $osrev_min >= 11) {
    $test->test_skip("These tests only run on Solaris 11 and later");
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

  # Because Solaris demands that you always run nscd, as it should.
  my @pgrep_cmd = qw(/bin/pgrep nscd);

  my ($nscd_pid) = qx{@pgrep_cmd}; chomp($nscd_pid);

  my $obj = $test->class_name->new(pid => $nscd_pid);

  isa_ok($obj, $test->class_name, 'Should create new object');
}


1;

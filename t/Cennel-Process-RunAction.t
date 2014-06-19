use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Test::Differences;
use Cennel::Process::RunAction;
use File::Temp;

sub src_repo ($) {
  my $files = $_[0];

  my $temp = File::Temp->newdir;

  (system "cd \Q$temp\E && git init") == 0 or die $?;
  for (keys %$files) {
    my $path = path ($temp)->child ($_);
    $path->parent->mkpath;
    $path->spew ($files->{$_});
    (system "cd \Q$temp\E && git add \Q$path\E") == 0 or die $?;
  }
  (system "cd \Q$temp\E && git commit -m new") == 0 or die $?;

  return $temp;
} # src_repo

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        run 'touch', 'hoge.txt';
      };
      1;
    },
  };

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok $repo_path->is_dir;
      ok $repo_path->child ('hoge.txt')->is_file;

      undef $action;
      my $timer; $timer = AE::timer 1, 0, sub {
        test {
          ok not $repo_path->is_dir;
          done $c;
          undef $c;
          undef $timer;
        } $c;
      };
    } $c;
  });
} n => 5, name => 'cinnamon task succeeded';

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        die "failed";
      };
      1;
    },
  };

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {error => 1};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok $repo_path->is_dir;

      undef $action;
      my $timer; $timer = AE::timer 1, 0, sub {
        test {
          ok not $repo_path->is_dir;
          done $c;
          undef $c;
          undef $timer;
        } $c;
      };
    } $c;
  });
} n => 4, name => 'cinnamon task failed';

test {
  my $c = shift;

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => 'git://notfound.test/hoge/fuga',
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {error => 1};

      my $repo_path = $action->temp_repo_path;
      ok not $repo_path->is_dir;

      done $c;
      undef $c;
    } $c;
  });
} n => 2, name => 'git clone failed';

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        run 'touch', 'hoge.txt';
      };
      1;
    },
  };
  (system "cd \Q$src_repo\E && git checkout -b foo && touch fuga.txt && git add fuga.txt && git commit -m fuga && git checkout master") == 0 or die $?;

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    git_branch => 'foo',
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok $repo_path->is_dir;
      ok $repo_path->child ('hoge.txt')->is_file;
      ok $repo_path->child ('fuga.txt')->is_file;
      done $c;
      undef $c;
    } $c;
  });
} n => 5, name => 'branch found';

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        run 'touch', 'hoge.txt';
      };
      1;
    },
  };

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    git_branch => 'foo',
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {error => 1};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok not $repo_path->child ('hoge.txt')->is_file;
      done $c;
      undef $c;
    } $c;
  });
} n => 3, name => 'branch not found';

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        run 'touch', 'hoge.txt';
      };
      1;
    },
  };
  my $rev = `cd \Q$src_repo\E && git rev-parse HEAD`;
  chomp $rev;
  (system "cd \Q$src_repo\E && touch fuga.txt && git add fuga.txt && git commit -m fuga") == 0 or die $?;

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    git_revision => $rev,
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok $repo_path->is_dir;
      ok $repo_path->child ('hoge.txt')->is_file;
      ok not $repo_path->child ('fuga.txt')->is_file;
      done $c;
      undef $c;
    } $c;
  });
} n => 5, name => 'revision found';

test {
  my $c = shift;

  my $src_repo = src_repo {
    'config/deploy.pl' => q{
      use Cinnamon::DSL;
      role default => ['host1'];
      task action => sub {
        my ($host, @args) = @_;
        run 'touch', 'hoge.txt';
      };
      1;
    },
  };

  my $action = Cennel::Process::RunAction->new_from_def ({
    git_url => '' . $src_repo,
    git_revision => 'hogefuga',
    cinnamon_role => 'default',
    cinnamon_task => 'action',
  });

  $action->run_as_cv->cb (sub {
    my $result = $_[0]->recv;
    test {
      eq_or_diff $result, {error => 1};

      my $repo_path = $action->temp_repo_path;
      isnt ''.$repo_path, ''.$src_repo;
      ok $repo_path->is_dir;
      ok not $repo_path->child ('hoge.txt')->is_file;
      done $c;
      undef $c;
    } $c;
  });
} n => 4, name => 'revision not found';

run_tests;

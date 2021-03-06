package Cennel::Web;
use strict;
use warnings;
use Wanage::HTTP;
use Warabe::App;
use Karasuma::Config::JSON;
use JSON::Functions::XS qw(json_bytes2perl);
use Web::UserAgent::Functions qw(http_post);
use Cennel::Process::RunAction;

my $Config = Karasuma::Config::JSON->new_from_env;

sub psgi_app ($$) {
  my ($class, $rules) = @_;
  return sub {
    ## This is necessary so that different forked siblings have
    ## different seeds.
    srand;

    ## XXX Parallel::Prefork (?)
    delete $SIG{CHLD} if defined $SIG{CHLD} and not ref $SIG{CHLD};

    my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
    my $app = Warabe::App->new_from_http ($http);
    return $http->send_response (onready => sub {
      $app->execute (sub {
        $class->process ($app, $rules);
      });
    });
  };
}

sub process ($$$) {
  my ($class, $app, $rules) = @_;

  if (@{$app->path_segments} == 1 and
      $app->path_segments->[0] eq 'hook') {
    # /hook
    $app->requires_request_method ({POST => 1});
    $app->requires_valid_content_length;
    $app->requires_mime_type ({'application/json' => 1});
    $app->requires_same_origin
        if not $app->http->request_method_is_safe and
           defined $app->http->get_request_header ('Origin');

    ## <https://developer.github.com/webhooks/>
    ## <https://developer.github.com/v3/activity/events/types/#pushevent>
    my $event = $app->http->get_request_header ('X-Github-Event');
    if (defined $event and $event eq 'push') {
      my $input = json_bytes2perl ${$app->http->request_body_as_ref};
      return $app->throw_error (422) unless ref $input eq 'HASH';
      my $name = $app->bare_param ('repo');
      my $old_revision = $input->{before};
      my $revision = $input->{after};
      my $branch;
      if (defined $input->{ref} and
          $input->{ref} =~ m{\Arefs/heads/(.+)\z}) {
        $branch = $1;
      }
      if (defined $name and defined $branch and
          $rules->{$name}->{$branch}) {
        my $def = {
          git_branch => $branch,
          git_revision => $revision,
          %{$rules->{$name}->{$branch}},
        };
        my $act = Cennel::Process::RunAction->new_from_def ($def);
        $act->onlog (sub {
          my ($msg, %args) = @_;
          warn "[@{[$args{channel} || '']}] $msg\n" if defined $msg;
        });
        $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 0, sprintf "%s %s (%s -> %s) updating...", $name, $branch, (substr $old_revision, 0, 10), substr $revision, 0, 10);
        $act->run_as_cv->cb (sub {
          my $result = $_[0]->recv;
          if ($result->{error}) {
            $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 1, sprintf "%s %s (%s -> %s) update failed", $name, $branch, (substr $old_revision, 0, 10), substr $revision, 0, 10);
            return $app->send_error (500);
          } else {
            $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 0, sprintf "%s %s (%s -> %s) updated%s", $name, $branch, (substr $old_revision, 0, 10), (substr $revision, 0, 10), defined $def->{message} ? ' ' . $def->{message} : '');
            return $app->send_error (200);
          }
        });
        return $app->throw;
      } else {
        return $app->throw_error (204);
      }

    } elsif (defined (my $name = $app->text_param ('name')) and
             (my $branch = 'master')) {
      if ($rules->{$name}->{$branch}) {
        my $def = {
          git_branch => $branch,
          #git_revision => $revision,
          %{$rules->{$name}->{$branch}},
        };
        $app->http->set_status (202);
        $app->http->set_response_header ('Content-Type' => 'text/plain; charset=utf-8');
        my $act = Cennel::Process::RunAction->new_from_def ($def);
        $act->onlog (sub {
          my ($msg, %args) = @_;
          if (defined $msg) {
            warn "[@{[$args{channel} || '']}] $msg\n";
            #$app->http->send_response_body_as_ref (\$msg);
            #$app->http->send_response_body_as_ref (\"\n");
            $app->http->send_response_body_as_ref (\".");
          }
        });
        $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 0, sprintf "%s %s updating...", $name, $branch);
        $act->run_as_cv->cb (sub {
          my $result = $_[0]->recv;
          if ($result->{error}) {
            $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 1, sprintf "%s %s update failed", $name, $branch);
            $app->http->send_response_body_as_ref (\"failed");
            return $app->http->close_response_body;
          } else {
            $class->ikachan ($def->{ikachan_url_prefix}, $def->{ikachan_channel}, 0, sprintf "%s %s updated%s", $name, $branch, defined $def->{message} ? ' ' . $def->{message} : '');
            $app->http->send_response_body_as_ref (\"done");
            return $app->http->close_response_body;
          }
        });
        return $app->throw;
      } else {
        return $app->throw_error (400);
      }
      
    } else {
      return $app->throw_error (204);
    }
  }
  
  return $app->throw_error (404);
} # process

my $ThisHost = `hostname`;
chomp $ThisHost;

my $AppName = __PACKAGE__;
$AppName =~ s{::Web$}{};

sub ikachan {
  my ($class, $url_prefix, $channel, $privmsg, $msg) = @_;
  return unless defined $url_prefix;
  http_post
    url => $url_prefix . ($privmsg ? 'privmsg' : 'notice'),
    params => {
      channel => $channel,
      message => sprintf "%s[%s] %s", $AppName, $ThisHost, $msg,
    },
    anyevent => 1,
    cb => sub {
      #
    };
}

1;

=head1 LICENSE

Copyright 2014 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

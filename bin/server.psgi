# -*- perl -*-
use strict;
use warnings;
use Path::Tiny;
use Cennel::Web;
use JSON::Functions::XS qw(json_bytes2perl);

my $rules = json_bytes2perl path ($ENV{CENNEL_RULES_FILE} or die "No |CENNEL_RULES_FILE|")->slurp;

return Cennel::Web->psgi_app ($rules);

## License: Public Domain.

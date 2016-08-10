#!/usr/bin/perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Copy;
use File::Find;
use File::Compare;
use File::Basename;
use Cwd;
use File::Spec;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use JSON;
use Config::Simple;

# Load configuration
my $dirname = dirname(__FILE__);
my $config = new Config::Simple();
$config->read($dirname . '/config.cfg') or die $config->error();

my $PATH_ROOT = $config->param( 'PATH_ROOT' );
my $PATH_ROOT_WITH_SLASH = $config->param( 'PATH_ROOT_WITH_SLASH' );
my $MEDIA_ROOT = $config->param( 'MEDIA_ROOT' );
my $USERS_ROOT = $config->param( 'USERS_ROOT' );
my $WEB_ROOT = $config->param( 'WEB_ROOT' );
my $SLACK_URL = $config->param( 'SLACK_URL' );
my $SLACK_CHANNEL = $config->param( 'SLACK_CHANNEL' );
my $SLACK_USERNAME = $config->param( 'SLACK_USERNAME' );
my $SLACK_ICON_EMOJI = $config->param( 'SLACK_ICON_EMOJI' );

my $REGEX_PATH_ROOT = quotemeta $PATH_ROOT;
my $REGEX_WEB_ROOT = quotemeta $WEB_ROOT;

# Create HTTP "client"
my $ua = LWP::UserAgent->new;
$ua->timeout(15);

if (!-e $MEDIA_ROOT)
{
  print "$MEDIA_ROOT does not exists\n";
  exit;
}

if (!-e $USERS_ROOT)
{
  print "$USERS_ROOT does not exists\n";
  exit;
}

# Ignored file extension in the notifications
my %ignored = ();
$ignored{".srt"} = 1;
$ignored{".ass"} = 1;
$ignored{".idx"} = 1;
$ignored{".sub"} = 1;

print "Moving files from $USERS_ROOT to $MEDIA_ROOT\n";

opendir USERS_DIR, "$USERS_ROOT" or die "Couldn't open the $MEDIA_ROOT: $!";

chdir $USERS_ROOT;

my $messageTotal = '';

while ($_ = readdir (USERS_DIR))
{
  if ($_ ne '..' && $_ ne '.') {
    my $user = $_;
    if (-d $user) {
      chdir $user;

      move_media("Series", "^Series/.* - \\d\\d\\d\\d/.*");
      move_media("Movies", "^Movies/.*");
      move_media("Games", "^Games/.*/.*/.*");
      move_media("OS", "^OS/.*/.*");
      move_media("Softwares", "^Softwares/.*/.*");
      move_media("Documentaries", "^Documentaries/.*");
      move_media("Shows", "^Shows/.*");

      ## Books
      move_media("Books", "^Books/comics/[a-z][a-z]/.*");
      move_media("Books", "^Books/mangas/[a-z][a-z]/.*");
      move_media("Books", "^Books/novels/[a-z][a-z]/.*");
      move_media("Books", "^Books/documentation/computer/programming/[a-z][a-z]/.*");
      move_media("Books", "^Books/documentation/computer/softwares/[a-z][a-z]/.*");
      move_media("Books", "^Books/documentation/computer/os/[a-z][a-z]/.*");
      move_media("Books", "^Books/documentation/cooking/[a-z][a-z]/.*");

# Rules to be defined
#      move_media("Music", "^Music/.*/\\d\\d\\d\\d - .*/.*");

      chdir "..";
    }
  }
}

if (length($messageTotal) > 0) {
  # Send slack notification
  my $payload =
  {
    channel => $SLACK_CHANNEL,
    username => $SLACK_USERNAME,
    icon_emoji => $SLACK_USERNAME,
    text => $messageTotal
  };

  my $req = POST("${SLACK_URL}", ['payload' => encode_json($payload)]);
  $ua->request($req);
}

sub move_media
{
  my $media = $_[0];
  my $regexp = $_[1];

  if (-d $media)
  {
    find
    (
      sub
      {
        my $source = $File::Find::name;
        if (-f $_ && $source =~ $regexp) {  
          my $target = "$MEDIA_ROOT/$File::Find::name";
          my ($targetvolume,$targetdirectories,$targetfile) =  File::Spec->splitpath($target);
          print "Moving file \"$source\" to \"$target\"\n";
          make_path($targetdirectories, { mode => 0755 });

          if (-f $target && compare($_, $target) == 0) {
            # Target and source are identical, just clean the source
	    unlink($_);

            print "Deleting already existing \"$_\" file\n";
          } else {
            move($_, $target);

            # Force proper chmod for moved files (just in case)
            chmod 0644, $target;

            # Notifications
            my ($dir, $name, $ext) = fileparse($target, qr/\.[^.]*/);

            if (!exists($ignored{$ext})) {
              my $targetURL = $target;
              $targetURL =~ s/$REGEX_PATH_ROOT/$REGEX_WEB_ROOT/g;
              $targetURL =~ s/%/%25/g;
              $targetURL =~ s/ /%20/g;

              my $targetSuffix = substr($target, length($PATH_ROOT));

              # Get owner
              my $uid = (stat $target)[4];
              my $user = `mysql --database="di" -se "select login from users where uid='$uid'"`;
              $user =~ s/^\s+|\s+$//g;

              # Update notification message
              if (length($messageTotal) > 0) {
		  $messageTotal .= "\n";
              }
              $messageTotal .= "$user uploaded <$targetURL|$targetSuffix>";
            }
          }
        }
      },
      $media
    );
  }
}

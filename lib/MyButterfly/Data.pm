use MyButterfly::Conf;
use JSON::Tiny;
use MyButterfly::Utils;

class MyButterfly::Data {


  has Hash $.project-cache;

  method !cache-in-sync ($p) {

  # right caching does not work
  # so just unconditionally
  # sync always

  return False;

  # cache does not exist
  # we need to build the one

  return False unless $!project-cache{$p.basename}:exists;

  if "{$p}/updates".IO ~~ :d {

    my @updates = dir "{$p}/updates";

    # updates found, clean queue
    # and notify to update cache

    if @updates.elems > 0 {

      say "project $p recieved {@updates.elems} updates, need to update cache";

      for @updates -> $i {
        unlink $i
      }

      return False;

    }

  }

  return True;

  }


method sync-cache ($p, Mu $user, Mu $token) {

      return if self!cache-in-sync($p);

      #say "update cache, project: $p";

      my $help-wanted = False;

      my $has-recent-release = False;

      my %meta = from-json("$p/meta.json".IO.slurp);

      %meta<points> = dir("$p/ups/").elems;

      %meta<reviews-cnt> = dir("$p/reviews/data").elems;

      if check-user($user, $token) and "$p/ups/$user".IO ~~ :e {
        %meta<voted> = True
      } else {
        %meta<voted> = False
      }

      %meta<date> = %meta<creation-date>; # just an alias

      %meta<creation-date-str> = DateTime.new(
        %meta<creation-date>,
        formatter => {
          sprintf '%02d.%02d.%04d, %02d:%02d', 
          .day, .month, .year, .hour, .minute
        }
      );

      if "$p/state.json".IO ~~ :e {

        %meta<update-date> = "$p/state.json".IO.modified;

        %meta<event> = from-json("$p/state.json".IO.slurp);

        %meta<event><event-str> = event-to-label(%meta<event><action>);

      } else {

        %meta<update-date> = %meta<date>;

        %meta<event> = %( action => "project added" );

        %meta<event><event-str> = event-to-label(%meta<event><action>);

      }

      %meta<date-str> = date-to-x-ago(%meta<update-date>.DateTime);

      %meta<add_by> ||= "melezhik";

      %meta<twitter-hash-tag> = join ",", (
        "mybfio", 
        "SoftwareProjectsReviews",
        %meta<language><>.map({ .subst('+','PLUS',:g).subst('Raku','Rakulang',:g) }),
    );

      if %meta<owners> {
          %meta<owners-str> = %meta<owners><>.join(" ");
      }

    if "$p/state.json".IO ~~ :e {

        %meta<update-date> = "$p/state.json".IO.modified;

        %meta<event> = from-json("$p/state.json".IO.slurp);

        %meta<event><event-str> = event-to-label(%meta<event><action>);

     } else {

        %meta<update-date> = %meta<date>;

        %meta<event> = %( action => "project added" );

        %meta<event><event-str> = event-to-label(%meta<event><action>);

     }

     %meta<releases> = [];

     if "{$p}/releases".IO ~~ :d {

       my $week-ago = DateTime.now() - Duration.new(60*60*24*7);

       for dir("{$p}/releases/") -> $r {

          my %data = from-json($r.IO.slurp());

          push %meta<releases>, %data;

          my $r-id; $r.IO.basename ~~ /(\d+) '.'/;

          $r-id = "$0";

          #say $r-id;

          if DateTime.new( 
              Instant.from-posix($r-id)
            ) >= $week-ago {
              $has-recent-release = True
          }

       }

     }

    my @reviews;

    my $month-ago = DateTime.now() - Duration.new(60*60*24*30);

    for dir("{$p}/reviews/data") -> $r {

      my %meta;

      %meta<data> = $r.IO.slurp;
        
      %meta<data-html> = mini-parser(%meta<data>);
    
      my %rd = review-from-file($r);

      %meta<author> = %rd<author>;

      %meta<date> = %rd<date>;

      %meta<id> = %rd<id>;

      %meta<date-str> = "{%rd<date>}";

      if check-user($user, $token) and $user eq %meta<author> {
        %meta<edit> = True;
      } else {
        %meta<edit> = False
      }

      if "{$p}/reviews/points/{%rd<basename>}".IO ~~ :e {
        %meta<points> = "{$p}/reviews/points/{%rd<basename>}".IO.slurp;
        %meta<points-str> = score-to-label(%meta<points>);

        if %meta<points> == -2 and %meta<date> >= $month-ago {
            $help-wanted = True
        }

      }

      if "{$p}/reviews/ups/{%meta<author>}_{%meta<id>}".IO ~~ :d {
        %meta<ups> = dir("{$p}/reviews/ups/{%meta<author>}_{%meta<id>}").elems;
        if check-user($user, $token) and "{$p}/reviews/ups/{%meta<author>}_{%meta<id>}/{$user}".IO ~~ :e {
          %meta<voted> = True;
        } else {
          %meta<voted> = False;
        }
      } else {
        %meta<ups> = 0;
        %meta<voted> = False;
      }

      %meta<ups-str> = "{uniparse 'TWO HEARTS'} : {%meta<ups>}";

      %meta<replies> = [];

      if "{$p}/reviews/replies/{%rd<basename>}".IO ~~ :d {

        for dir("{$p}/reviews/replies/{%rd<basename>}") -> $rp {

          my %rd = review-from-file($rp);
          
          my %reply;

          %reply<data> = $rp.IO.slurp;

          %reply<data-html> = mini-parser(%reply<data>);

          %reply<author> = %rd<author>;

          %reply<date> = %rd<date>;

          %reply<date-str> = "{%rd<date>}";

          %reply<id> = %rd<id>;

          if check-user($user, $token) and $user eq %reply<author> {
            %reply<edit> = True;
            %meta<replied> = True;
          } else {
            %reply<edit> = False
          }

          push %meta<replies>, %reply;

        }

        %meta<replies> = %meta<replies>.sort({.<date>}).reverse;

      }

      push @reviews, %meta;

    }

    %meta<reviews> = @reviews;

    %meta<has-recent-release> = $has-recent-release;
    %meta<help-wanted> = $help-wanted;

    %meta<attributes> = []; # this one is reserved for the future
    %meta<attributes-str> = [];

    if $help-wanted {
      push %meta<attributes>, "help-wanted";
      push %meta<attributes-str>, uniparse "Raised Hand";
    }

    if $has-recent-release {
      push %meta<attributes>, "has-recent-release";   
      push %meta<attributes-str>, uniparse "Package";
    }

    $!project-cache{$p.basename} = %meta; # update cache

    return;

}

} # end of class

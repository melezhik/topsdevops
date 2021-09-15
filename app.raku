use Cro::HTTP::Server;
use Cro::HTTP::Router;
use Cro::WebApp::Template;
use Cro::HTTP::Client;

use MyButterfly::HTML;

use JSON::Tiny;


my $application = route { 

  get -> :$user is cookie {

    my @projects;

    for dir("{cache-root()}/projects/") -> $p {

      my %meta = from-json("$p/meta.json".IO.slurp);

      %meta<points> = dir("$p/ups/").elems;

      %meta<reviews-cnt> = dir("$p/reviews/data").elems;

      if $user and "$p/ups/$user".IO ~~ :e {
        %meta<voted> = True
      } else {
        %meta<voted> = False
      }

      push @projects, %meta;

    }

    template 'templates/main.crotmp', {
      title => title(),
      http-root => http-root(),
      user => $user, 
      css => css(), 
      navbar => navbar($user||""),
      projects => @projects.sort({ .<points> }).reverse
    }

  }

  get -> 'project', $project, 'reviews', :$user is cookie {

    my @reviews;

    my $has-user-review = False;

    for dir("{cache-root()}/projects/$project/reviews/data") -> $r {

      my %meta;

      %meta<data> = $r.IO.slurp;

      %meta<author> = $r.IO.basename;

      %meta<date> = $r.IO.modified;

      %meta<date-str> = DateTime.new(
        $r.IO.modified,
        formatter => { sprintf "%02d:%02d %02d/%02d/%02d", .hour, .minute, .day, .month, .year }
      );

      if $user and $user eq %meta<author> {
        %meta<edit> = True;
        $has-user-review = True;
      } else {
        %meta<edit> = False
      }

      if "{cache-root()}/projects/$project/reviews/points/{%meta<author>}".IO ~~ :e {
        %meta<points> = "{cache-root()}/projects/$project/reviews/points/{%meta<author>}".IO.slurp;
        %meta<points-str> = "{uniparse 'BUTTERFLY'}" x %meta<points>;
      }

      push @reviews, %meta;

    }

    template 'templates/reviews.crotmp', {
      title => title(),
      http-root => http-root(),
      user => $user, 
      css => css(), 
      navbar => navbar($user||""),
      project => $project,
      has-user-review => $has-user-review,
      reviews => @reviews.sort({ .<date> }).reverse
    }
  }


  get -> 'project', $project, 'edit-review', :$user is cookie {

    if $user {

      my %review; 

      if "{cache-root()}/projects/$project/reviews/data/$user".IO ~~ :e {
        %review<data> = "{cache-root()}/projects/$project/reviews/data/$user".IO.slurp;
        say "read data from {cache-root()}/projects/$project/reviews/data/$user";
      } else {
        %review<data> = ""
      }

      if "{cache-root()}/projects/$project/reviews/points/$user".IO ~~ :e {
        %review<points> = "{cache-root()}/projects/$project/reviews/points/$user".IO.slurp;
        say "read points from {cache-root()}/projects/$project/reviews/points/$user - {%review<points>}";
      }

      template 'templates/edit-review.crotmp', {
        title => title(),
        http-root => http-root(),
        user => $user, 
        css => css(), 
        navbar => navbar($user||""),
        project => $project,
        review => %review
      }

    } else {

      redirect :permanent, "{http-root()}/login-page?message=you need to sign in to edit or write eviews";

    }
  }

  post -> 'project', $project, 'edit-review', :$user is cookie {

    if $user {

      request-body -> (:$data, :$points) {

        "{cache-root()}/projects/$project/reviews/data/$user".IO.spurt($data);

        my %review; 

        say "points - $points";

        if $points {
          say "update points {cache-root()}/projects/$project/reviews/points/$user - $points";
          "{cache-root()}/projects/$project/reviews/points/$user".IO.spurt($points);
          %review<points> = $points;
        } else {

          if "{cache-root()}/projects/$project/reviews/points/$user".IO ~~ :e {
            %review<points> = "{cache-root()}/projects/$project/reviews/points/$user".IO.slurp;
            say "read points from {cache-root()}/projects/$project/reviews/points/$user - {%review<points>}";
          }

        }

         created "/project/$project/edit-review";

         %review<data> = $data;
         
         template 'templates/edit-review.crotmp', {
           title => title(),
           http-root => http-root(),
           user => $user,
           message => "review updated", 
           css => css(), 
           navbar => navbar($user||""),
           project => $project,
           review => %review
        }

      };

    } else {

      redirect :permanent, "{http-root()}/login-page?message=you need to sign in to edit reviews";

    }
  }

  get -> 'about', :$user is cookie {

    template 'templates/about.crotmp', {
      title => title(),
      http-root => http-root(),
      css => css(), 
      navbar => navbar($user||""),
      butterfly => "{uniparse 'BUTTERFLY'}"
    }
  }

  get -> 'oauth2', :$state, :$code {

      say "request token from https://github.com/login/oauth/access_token";

      my $resp = await Cro::HTTP::Client.get: 'https://github.com/login/oauth/access_token',
        headers => [
          "Accept" => "application/json"
        ],
        query => { 
          redirect_uri => "http://161.35.115.119/mbf/oauth2",
          client_id => %*ENV<OAUTH_CLIENT_ID>,
          client_secret => %*ENV<OAUTH_CLIENT_SECRET>,
          code => $code,
          state => $state,    
        };

      my $data = await $resp.body-text();

      my %data = from-json($data);

      say "response recieved - {%data.perl} ... ";

      if %data<access_token>:exists {

        say "token recieved - {%data<access_token>} ... ";

        my $resp = await Cro::HTTP::Client.get: 'https://api.github.com/user',
          headers => [
            "Accept" => "application/vnd.github.v3+json",
            "Authorization" => "token {%data<access_token>}"
          ];

        my $data2 = await $resp.body-text();
  
        my %data2 = from-json($data2);

        say "set user to {%data2<login>}";

        set-cookie 'user', %data2<login>;

      }

      redirect :permanent, "{http-root()}/";
       
  } 

  get -> 'login-page', :$message {

    template 'templates/login-page.crotmp', {
      title => title(),
      http-root => http-root(),
      message => $message || "sign in using your github account",
      css => css(), 
      navbar => navbar(""),
    }
  }

  get -> 'login' {
    redirect :permanent,
      "https://github.com/login/oauth/authorize?client_id={%*ENV<OAUTH_CLIENT_ID>}&state={%*ENV<OAUTH_STATE>}"
  }

  get -> 'logout' {
    set-cookie 'user', "";
    redirect :permanent, "{http-root()}/";
  }

  get -> 'project', $project, 'up', :$user is cookie {

    if $user {

      unless "{cache-root()}/projects/$project/ups/$user".IO ~~ :e {
        say "up {cache-root()}/projects/$project/ups/$user";
        "{cache-root()}/projects/$project/ups/$user".IO.spurt("");
      }
    
      redirect :permanent, "{http-root()}/";

    } else {

      redirect :permanent, "{http-root()}/login-page?message=you need to sign in to vote";

    }
      
  }

  get -> 'project', $project, 'down', :$user is cookie {

    if $user {

      if "{cache-root()}/projects/$project/ups/$user".IO ~~ :e {
        say "down {cache-root()}/projects/$project/ups/$user";
        unlink "{cache-root()}/projects/$project/ups/$user";
      }
    
      redirect :permanent, "{http-root()}/";

    } else {

      redirect :permanent, "{http-root()}/login-page";

    }
      
  }

  get -> 'icons', *@path {

    cache-control :public, :max-age(3000);

    static 'icons', @path;

  }
}

my Cro::Service $service = Cro::HTTP::Server.new:
    :host<0.0.0.0>, :port<6000>, :$application;

$service.start;

react whenever signal(SIGINT) {
    $service.stop;
    exit;
}

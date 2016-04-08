#!/usr/bin/env perl

# query a random set of feeds and generate a list of feedly stories that would be added to media cloud if we were to run
# a feedly import for that feed

# usage: $0 < num_feeds >

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use Encode;

use MediaWords::DB;
use MediaWords::ImportStories::Feedly;
use MediaWords::Util::CSV;

sub main
{
    my ( $num_feeds ) = @ARGV;

    my $db = MediaWords::DB::connect_to_db;

    my $feeds = $db->query( <<SQL, $num_feeds )->hashes;
select * from feeds where feed_status = 'active' order by random() limit ( ? * 10 )
SQL

    my $dates = [];

    my $validate_stories = [];

    my $feed_data = [];

    my $scraped_feeds = [];
    for my $feed ( @{ $feeds } )
    {
        say STDERR "feed: " . scalar( @{ $scraped_feeds } ) . " / $num_feeds";

        my $import = MediaWords::ImportStories::Feedly->new(
            db       => $db,
            media_id => $feed->{ media_id },
            dry_run  => 1,
            feed_url => $feed->{ url }
        );

        my $import_stories;

        eval { $import_stories = $import->scrape_stories(); };
        warn( $@ ) if ( $@ );

        my $new_stories = $import->module_stories();

        next unless ( $new_stories && @{ $new_stories } );

        my $import_stories_lookup = {};
        map { $import_stories_lookup->{ $_->{ guid } } = 1 } @{ $import_stories };

        map { $_->{ import } = $import_stories_lookup->{ $_->{ guid } } || 0 } @{ $new_stories };

        map { $_->{ _r } = rand() } @{ $new_stories };

        splice( @{ $new_stories }, 10 );

        map {
            $_->{ feeds_id } = $feed->{ feeds_id };
            $_->{ dup_stories_id } ||= 0;
            delete( $_->{ _r } );
            delete( $_->{ description } )
        } @{ $new_stories };

        push( @{ $validate_stories }, @{ $new_stories } );

        $feed->{ feedly_start_date }     = $import->start_date;
        $feed->{ feedly_end_date }       = $import->end_date;
        $feed->{ feedly_stories }        = scalar( @{ $new_stories } );
        $feed->{ feedly_import_stories } = scalar( @{ $import_stories } );

        push( @{ $scraped_feeds }, $feed );

        last if ( scalar( @{ $scraped_feeds } ) >= $num_feeds );
    }

    # binmode( STDOUT, 'utf8' );
    #
    # map { say $_->{ title }; } @{ $validate_stories };

    print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $validate_stories ) );
    print( MediaWords::Util::CSV::get_hashes_as_encoded_csv( $scraped_feeds ) );
}

main();
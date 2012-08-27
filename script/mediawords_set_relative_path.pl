#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;
use MediaWords::Util::XML;

use XML::LibXML;
use MIME::Base64;
use Encode;
use List::Util qw (min);
use Parallel::ForkManager;

sub set_relative_path_downloads
{
    my ( $start_downloads_id, $end_downloads_id, $batch_number ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $batch_information = '';

    if ( defined( $batch_number ) )
    {
        $batch_information = "Batch $batch_number";
    }

    my $max_downloads_id_message = '';
    if ( defined( $max_downloads_id ) )
    {
        $max_downloads_id_message = " max overall downloads_id $max_downloads_id";
    }

    say STDERR "$batch_information downloads_id $cur_downloads_id -- $end_downloads_id  $max_downloads_id_message";

    my $download = $db->query(
"UPDATE downloads set relative_file_path = get_relative_file_path( path ) where downloads_id >= ?  and downloads_id <= ? ",
        $cur_downloads_id, $end_downloads_id
    )->hash();

    return;
}

sub set_relative_path_all_downloads
{

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_downloads_id ) =
      $db->query( " SELECT max( downloads_id) from downloads where type = 'feed' and state = 'success' " )->flat();

    my ( $min_downloads_id ) = $db->query( " SELECT min( downloads_id) from downloads " )->flat();

    #Make sure the file start and end ranges are multiples of 1000
    my $start_downloads_id = int( $min_downloads_id / 1000 ) * 1000;

    Readonly my $download_batch_size => 100;

    my $batch_number = 0;

    my $pm = new Parallel::ForkManager( 15 );
    while ( $start_downloads_id <= $max_downloads_id )
    {
        unless ( $pm->start )
        {

            set_relative_path_downloads( $start_downloads_id, $start_downloads_id + $download_batch_size, $batch_number );
            $pm->finish;
        }

        $start_downloads_id += $download_batch_size;
        $batch_number++;

        #exit;
    }

    say "Waiting for children";

    $pm->wait_all_children;

}

# fork of $num_processes
sub main
{
    my ( $num_processes ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    set_relative_path_all_downloads();
}

main();

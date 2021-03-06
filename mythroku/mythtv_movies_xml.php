<?php

//get the local info from the settings file
require_once './settings.php';

//print "\n***HOSTNAME:" . getHostname() . "\n";
//print "\n***HTTP_CLIENT_IP:" . $_SERVER['HTTP_CLIENT_IP'] . "\n";
//print "\n***REMOTE_ADDR:" . $_SERVER['REMOTE_ADDR'] . "\n";


$conditions = array('conditions' => array('filename like ? AND host > ?', '%.mp4', '')); //using combination of Storage Group and locally hosted video the host value in videometadata is currently only set for the backend machine.  TODO: check for actual host name
$order = array('order' => 'insertdate ASC');
if (isset($_GET['sort'])) //there is not GET in the session when running php from CLI
{
    switch($_GET['sort'])
    {
        case "date":
            $order = array('order' => 'insertdate DESC');
            break;
        case "title":
            $order = array('order' => 'title ASC');
            break;
        case "genre":
            $order = array('order' => 'category ASC');
            break;
        case "year":
            $order = array('order' => 'year DESC');
            break;
        default:
            break;
    }	
}

$item = VideoMetadata::all( array_merge($conditions, $order) );
	
//print the xml header
print "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?> 
	<feed>
	<!-- resultLength indicates the total number of results for this feed -->
	<resultLength>" . count($item) . "</resultLength>
	<!-- endIndix  indicates the number of results for this *paged* section of the feed -->
	<endIndex>" . count($item)  . "</endIndex>";

	$storage = StorageGroup::first( array('conditions' => array('groupname = ?', 'Videos')) );
	
    foreach ($item as $key => $value)
    {   
    	$category = VideoCategory::first( array('conditions' => array('intid = ?', $value->category)) );    	
    	$streamUrl = implode("/", array_map("rawurlencode", explode("/", $MythTVvideos . $value->filename)));

	    //print out the record in xml format for roku to read 
		print "	
		<item sdImg=\"" . $WebServer . "/" . $MythRokuDir . "/image.php?image=" . rawurlencode($value->coverfile) . "\" hdImg=\"" . $WebServer . "/" . $MythRokuDir . "/image.php?image=" . rawurlencode($value->coverfile) . "\">
			<title>" . htmlspecialchars(preg_replace('/[^(\x20-\x7F)]*/','', $value->title )) . "</title>
			<contentId>" . print_r(1000+$key,true) . "</contentId>
			<contentType>Movies</contentType>
			<contentQuality>". $RokuDisplayType . "</contentQuality>
			<media>
				<streamFormat>mp4</streamFormat>
				<streamQuality>". $RokuDisplayType . "</streamQuality>
				<streamBitrate>". $BitRate . "</streamBitrate>
				<streamUrl>" . $WebServer . $streamUrl ."</streamUrl>
			</media>
			<synopsis>" . htmlspecialchars(preg_replace('/[^(\x20-\x7F)]*/','', $value->plot )) . "</synopsis>
			<genres>" . htmlspecialchars(preg_replace('/[^(\x20-\x7F)]*/','', $category->category )) . "</genres>
			<runtime>" .$value->length . "</runtime>
			<date>Year: " . $value->year . "</date>
			<tvormov>movie</tvormov>
			<starrating>" . $value->userrating * 10 ."</starrating>
		</item>";	
    }

print "</feed>";

?>


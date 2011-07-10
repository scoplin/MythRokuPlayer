<?php

//get the local info from the settings file
require_once './settings.php';

if (isset($_GET['basename']))
{
    $basefname = $_GET['basename'];
    $conditions = array('conditions' => array('basename = ? ', $basefname));
    $recordings = Recorded::all($conditions);
    if(count($recordings) != 1) {
        print "There are " . count($recordings) . " items with the basename: $basefname";
    }else{
        $recording = $recordings[0];
        $storage = StorageGroup::first( array('conditions' => array('groupname = ?', $recording->storagegroup)) );
        $fname = $storage->dirname . strtok($basefname, ".");
        
        print "\nhere we delete $recording->basename from the database."; 
        $recording->delete();
        
        foreach(glob($fname . "*") as $file){
            print "\nhere we delete $file from the filesyste."; 
            unlink($file);
        }
    }
}else{
    print "the 'basename' was not passed to this routine!";
}

?>


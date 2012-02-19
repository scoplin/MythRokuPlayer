<?php
require_once 'php-activerecord/ActiveRecord.php';

# Borrowed list of config files from classes/MythTV.php
# Note that the web user must be able to read the config file
# Typically this means they need to be added to the mythtv group
$ConfigFiles = array( '/usr/local/share/mythtv/mysql.txt',
                      '/usr/share/mythtv/mysql.txt',
                      '/usr/local/etc/mythtv/mysql.txt',
                      '/etc/mythtv/mysql.txt',
                      'mysql.txt' );

$config = load_config(find_config($ConfigFiles));
$localhost = $_SERVER['SERVER_ADDR'];
$WebServer = "http://$localhost/mythweb";      // include path to mythweb eg, http://yourip/mythweb
$MythRokuDir = "mythroku";                     // name of your mythroku directory in the mythweb folder
$RokuDisplayType = "HD";                       // set to the same as your Roku player under display type, HD or SD  
$BitRate = "1500";                             // bit rate of endcoded streams
$MysqlServer = $config['DBHostName'];  // mysql server ip/name
$MythTVdb = $config['DBName'];         // mythtv database name
$MythTVdbuser = $config['DBUserName']; // mythtv database user
$MythTVdbpass = $config['DBPassword']; // mythtv database password
$MythTVvideos = "/data/videos/";               // mythweb/data symbolic link to the storage group for mythvideos 

/* can use TimeOffset in mythconver.settings */
//date_default_timezone_set ( 'GMT' );
//date_default_timezone_set ( 'America/Chicago' );

ActiveRecord\DateTime::$DEFAULT_FORMAT = 'db';

$URL = "mysql://$MythTVdbuser:$MythTVdbpass@$MysqlServer/$MythTVdb";


ActiveRecord\Config::initialize(function($cfg)
{
    global $URL;
    
    $cfg->set_model_directory('.');
    $cfg->set_connections(array('PVR1' => $URL));
    
    $cfg->set_default_connection('PVR1');
});

class Recorded extends ActiveRecord\Model 
{ 
    static $table_name = 'recorded'; 

    function get_starttime() {
        return $this->read_attribute('starttime')->format('db');
    }    
}

class StorageGroup extends ActiveRecord\Model
{
    static $table_name = 'storagegroup';
}    

class VideoMetadata extends ActiveRecord\Model
{
    static $table_name = 'videometadata';
}    

class VideoCategory extends ActiveRecord\Model
{
    static $table_name = 'videocategory';
}    

//function to convert mysql timestamp to unix time
function convert_datetime($str) 
{
    list($date, $time) = explode(' ', $str);
    list($year, $month, $day) = explode('-', $date);
    list($hour, $minute, $second) = explode(':', $time);

    $timestamp = mktime($hour, $minute, $second, $month, $day, $year);

    return $timestamp;
}

function load_config($source)
{
    $config = array();
    $file = fopen($source, 'r');
    if (!$file) {
        $id = `whoami`;
        die("Failed to open $source as $id");
    }
    while (!feof($file)) {
        $line = trim(fgets($file));
        // skip comments and empty lines!
        if (strlen($line) === 0 || strpos($line, '#') === 0)
            continue;
        list ($public, $value) = explode('=', $line, 2);
        $config[$public] = $value;
    }
    fclose($file);
    return $config;
}

function find_config($configs)
{
    foreach ($configs as $config) {
        $config = realpath($config);
        if ($config) {
            return $config;
	    break;
        }
    }

    die("Cannot find a valid config file.\n");
}

?>

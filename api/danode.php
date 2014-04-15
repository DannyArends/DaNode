<?php
  $argvs = array_slice($argv, 0);
  parse_str(implode('&', $argvs), $_GET);

  function toS($_array){
    $size = count($_array);
    $ret = '[';
    foreach($_array as $i => $a){ 
      $ret .= '"'. $i . '":"' . $a .'"';
      if($size > 1){ $ret .= ', '; $size--; }
    }
    return($ret . ']');
  }

  function readConfig($argv){
    $idx = strpos(strrev($argv[0]),"/");
    $idx = strlen($argv[0])-strlen("/")-$idx;
    $configloc   = str_split($argv[0],$idx);
    $configloc   = $configloc[0]."/web.config";
    if(file_exists($configloc)){
      $configcont  = split("\n", file_get_contents($configloc));
      foreach($configcont as $line){
        if(substr($line,0,1) != '#' && chop($line) != ""){
          $marray = split('=', $line);
          $config[chop($marray[0])] = strrev(chop(strrev(chop($marray[1]))));
        }
      }
    }
    return $config;
  }

  $_COOKIE = Array();
  $_CONFIG = readConfig($argv);
  $f = fopen( 'php://stdin', 'r' );
  stream_set_blocking($f, 0);
  while(false !== ($line = fgets($f))){
    $marray = split('=', $line);
    if(isset($marray[0]) && isset($marray[1]) && isset($marray[2])){
      if($marray[0] == "SERVER"){
        $_SERVER[urldecode($marray[1])] = urldecode(chop($marray[2]));
      }else if($marray[0] == "COOKIE"){
        $_COOKIE[urldecode($marray[1])] = urldecode(chop($marray[2]));
      }else{
        $_POST[urldecode($marray[1])] = urldecode(chop($marray[2]));
      }
    }
  }
  fclose($f);

  $api_loaded = true;
  return 1;
?>

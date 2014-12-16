# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2014 Michael Daum http://michaeldaumconsulting.com
#
# This license applies to GenPDFWebkitPlugin *and also to any derivatives*
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

package Foswiki::Plugins::GenPDFWebkitPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Sandbox ();
use Error qw(:try);
use File::Path ();
use Encode ();
use File::Temp ();

our $VERSION = '1.60';
our $RELEASE = '1.60';
our $SHORTDESCRIPTION = 'Generate PDF using Webkit';
our $NO_PREFS_IN_TOPIC = 1;
our $baseTopic;
our $baseWeb;
our $doit = 0;

use constant TRACE => 0; # toggle me

###############################################################################
sub writeDebug {
  print STDERR "GenPDFWebkitPlugin - $_[0]\n" if TRACE;
}

###############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  if ($Foswiki::Plugins::VERSION < 2.0) {
    Foswiki::Func::writeWarning('Version mismatch between ',
    __PACKAGE__, ' and Plugins.pm');
    return 0;
  }

  my $query = Foswiki::Func::getCgiQuery();
  my $contenttype = $query->param("contenttype") || 'text/html';

  if ($contenttype eq "application/pdf") {
    $doit = 1;
    Foswiki::Func::getContext()->{static} = 1;
  } else {
    $doit = 0;
  }

  return 1;
}

###############################################################################
sub completePageHandler {
  #my($html, $httpHeaders) = @_;

  return unless $doit;

  my $siteCharSet = $Foswiki::cfg{Site}{CharSet};
  
  my $content = $_[0];

  unless ($siteCharSet =~ /utf\-8/i) {
    # convert to utf8
    $content = Encode::decode($siteCharSet, $content);
    $content = Encode::encode_utf8($content);
  }

  # remove left-overs
  $content =~ s/([\t ]?)[ \t]*<\/?(nop|noautolink)\/?>/$1/gis;
  $content =~ s/<!--.*?-->//g;
  $content =~ s/[\0-\x08\x0B\x0C\x0E-\x1F\x7F]+/ /g;

  # clean url params in anchors as prince can't generate proper xrefs otherwise;
  # hope this gets fixed in prince at some time
  $content =~ s/(href=["'])\?.*(#[^"'\s])+/$1$2/g;

  # rewrite some urls to use file://..
  $content =~ s/(<link[^>]+href=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;
  $content =~ s/(<img[^>]+src=["'])([^"']+)(["'])/$1.toFileUrl($2).$3/ge;

  # create temp files
  my $htmlFile = new File::Temp(SUFFIX => '.html', UNLINK => (TRACE ? 0 : 1));
  my $errorFile = new File::Temp(SUFFIX => '.log', UNLINK => (TRACE ? 0 : 1));

  # create output filename
  my ($pdfFilePath, $pdfFile) = getFileName($baseWeb, $baseTopic);

  # creater html file

  binmode($htmlFile);
  print $htmlFile $content;
  writeDebug("htmlFile=" . $htmlFile->filename);

  # create webkit command
  my $pubUrl = getPubUrl();
  my $pdfCmd = $Foswiki::cfg{GenPDFWebkitPlugin}{WebkitCmd} || 
    '$Foswiki::cfg{ToolsDir}/wkhtmltopdf -q --enable-plugins --outline --print-media-type %INFILE|F% %OUTFILE|F%';

  writeDebug("pdfCmd=$pdfCmd");
  writeDebug("BASEURL=$pubUrl");
  
  # execute
  my ($output, $exit) = Foswiki::Sandbox->sysCommand(
      $pdfCmd, 
      BASEURL => $pubUrl,
      OUTFILE => $pdfFilePath,
      INFILE => $htmlFile->filename,
      ERROR => $errorFile->filename,
    );

  local $/ = undef;

  writeDebug("errorFile=" . $errorFile->filename);
  writeDebug("htmlFile=" . $htmlFile->filename);

  my $error = '';
  if ($exit || TRACE) {
    $error = <$errorFile>;
  }

  writeDebug("error=$error");
  writeDebug("output=$output");

  if ($exit) {
    my $html = $content;
    my $line = 1;
    $html = '00000: '.$html;
    $html =~ s/\n/"\n".(sprintf "\%05d", $line++).": "/ge;
    throw Error::Simple("execution of wkhtmltopdf failed ($exit): \n\n$error\n\n$html");
  }

  # not using viewfile to let the web server decide how to deliver the static file
  #my $url = Foswiki::Func::getScriptUrl($baseWeb, $baseTopic, 'viewfile',
  #  filename=>$pdfFile,
  #  t=>time(),
  #);
  my $url = $Foswiki::cfg{PubUrlPath} . '/' . $baseWeb . '/' . $baseTopic . '/' . $pdfFile . '?t=' . time();

  my $query = Foswiki::Func::getCgiQuery();
  Foswiki::Func::redirectCgiQuery($query, $url);
}

###############################################################################
sub getFileName {
  my ($web, $topic) = @_;

  my $query = Foswiki::Func::getCgiQuery();
  my $fileName = $query->param("outfile") || 'genpdf_'.$topic.'.pdf';

  $fileName =~ s{[\\/]+$}{};
  $fileName =~ s!^.*[\\/]!!;
  $fileName =~ s/$Foswiki::regex{filenameInvalidCharRegex}//go;

  $web =~ s/\./\//g;
  my $filePath = Foswiki::Func::getPubDir().'/'.$web.'/'.$topic;
  File::Path::mkpath($filePath);

  $filePath .= '/'.$fileName;

  return ($filePath, $fileName);
}

###############################################################################
sub toFileUrl {
  my $url = shift;

  my $fileUrl = $url;

  if ($fileUrl =~ /^(?:$Foswiki::cfg{DefaultUrlHost})?$Foswiki::cfg{PubUrlPath}(.*)$/) {
    $fileUrl = $1;
    $fileUrl =~ s/\?.*$//;
    $fileUrl = "file://".$Foswiki::cfg{PubDir}.$fileUrl;
  } else {
    writeDebug("url=$url does not point to the local server");
  }

  writeDebug("url=$url, fileUrl=$fileUrl");
  return $fileUrl;
}

###############################################################################
sub modifyHeaderHandler {
  my ($hopts, $request) = @_;

  $hopts->{'Content-Disposition'} = "inline;filename=$baseTopic.pdf" if $doit;
}

###############################################################################
sub getPubUrl {
  my $session = $Foswiki::Plugins::SESSION;

  if ($session->can("getPubUrl")) {
    # pre 1.2
    return $session->getPubUrl(1);
  } 

  # post 1.2
  return Foswiki::Func::getPubUrlPath(absolute=>1);
}
1;

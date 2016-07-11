# ---+ Extensions
# ---++ GenPDFWebkitPlugin
# **PATH**
# wkhtmltopdf executable including complete path
# downloadable from http://code.google.com/p/wkhtmltopdf;
# note that this plugin comes with a wkhtmltopdf binary for linux in the tools directory.
$Foswiki::cfg{GenPDFWebkitPlugin}{WebkitCmd} = '/usr/bin/wkhtmltopdf -q --enable-plugins --outline --enable-external-links --enable-internal-links --print-media-type %INFILE|F% %OUTFILE|F%';
1;

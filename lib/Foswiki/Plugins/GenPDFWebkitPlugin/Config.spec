# ---+ Extensions
# ---++ GenPDFWebkitPlugin
# **PATH M**
# wkhtmltopdf executable including complete path
# downloadable from http://code.google.com/p/wkhtmltopdf
$Foswiki::cfg{GenPDFWebkitPlugin}{WebkitCmd} = $Foswiki::cfg{ToolsDir}.'/wkhtmltopdf -q %INFILE|F% %OUTFILE|F%';
1;

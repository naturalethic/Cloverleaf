try
{
  require('coffee-script');
  require(NSProcessInfo.processInfo().processName());
  Cloverleaf.loadMainNib();
  setInterval(function() {}, 60000);
}
catch (e)
{
  console.log(e);
}
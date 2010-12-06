try
{
  require('coffee-script');
  require(NSProcessInfo.processInfo().processName());
}
catch (e)
{
  console.log(e);
}
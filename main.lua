require 'bee'
local fs = require 'bee.filesystem'
MAKEDIR = fs.exe_path():parent_path()
package.path = (MAKEDIR / "scripts" / "?.lua"):string()
require 'main'

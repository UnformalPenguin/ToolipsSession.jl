<div align = "center"><img src = "https://github.com/ChifiSource/image_dump/blob/main/toolips/toolipssession.png" href = "https://toolips.app"></img></div>

### Full-stack web-development for Julia with toolips
Toolips Session is a Server Extension for toolips that enables full-stack web-development capabilities. This extension is loaded by default whenever the `Toolips.new_webapp` from the base toolips package is used. Ideally, your project would be setup that way instead of by adding this directly; but of course, you can still add this directly.
- [Documentation](https://doc.toolips.app/extensions/toolips_session/)
- [Toolips](https://github.com/ChifiSource/Toolips.jl)
- [Extension Gallery](https://toolips.app/?page=gallery&selected=session)
##### Step 1: Add ToolipsSession to your environment with Pkg
Start a toolips **webapp** to automatically add `ToolipsSession`:
```julia
Toolips.new_webapp("ModifierExample
```
Otherwise, you can add it from Pkg directly, just ensure [toolips](https://github.com/ChifiSource/Toolips.jl) is also added.
```julia
using Pkg; Pkg.add("ToolipsSession")
```
##### Step 2: Add ToolipsSession to your module, use on()
This code is copy-pastable, just ensure your environment has toolips added, then copy and paste the `pkg` command above, `using Pkg; Pkg.add("ToolipsSession")`. 
```julia
"""
## Toolips Session / Modifier Example
"""
module ModifierExample
using Toolips
using ToolipsSession

extensions = [Logger(), Session()]

function start(IP::String = "127.0.0.1", PORT::Integer = 8000)
    server = WebServer(IP, PORT, routes = rs, extensions = extensions)
    server.start()
    server
end

function home(c::Connection)
    myp = p("helloworld2", text = "hello world!", align = "left")
    on(c, myp, "click") do cm::ComponentModifier
        if cm[myp]["align"] == "left"
            cm[myp] = "align" => "center"
        elseif cm[myp]["align"] == "center"
            cm[myp] = "align" => "right"
        else
            cm[myp] = "align" => "left"
        end
    end
end
end
```
#### start the server
```julia
include("dev.jl")
```

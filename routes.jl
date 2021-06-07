using Genie.Router

using Base64
using Logging
using UUIDs

using HTTP: unescapeuri
using LRUCache
using MacroTools: postwalk
using Mustache
using Quantikz

const whitelist_symbols = [
    :P, :H, :Id, :U,
    :CNOT, :CPHASE, :SWAP,
    :MultiControl, :MultiControlU, :ClassicalDecision,
    :Measurement, :ParityMeasurement,
    :Noise, :NoiseAll,
    :Initialize
]
const MAX_LENGTH = 10000

const CACHE_SIZE = 5000
function eviction(k,v)
    @info "$(v).png"
    rm("$(v).png")
end
const filecache = LRU{String,UUID}(maxsize=CACHE_SIZE, finalizer=eviction) # TODO consider using hash instead of UUID
# TODO check that evictions always happen: there might be leaks when many cache misses happen at the same time

function parsecircuit(circuitstring)
  length(circuitstring) > MAX_LENGTH && return "the circuit string is too long to render on this free service: shorten the circuit or render it by installing Quantikz.jl on your computer"
  try
    parsed = Meta.parse(strip(circuitstring))
    parsed.head ∉ [:vect,:tuple] && return "the provided string does not look like a list (you should use commas for separators and delineate with `[` and `]`)"
    all(parsed.args) do x
      isa(x, Expr) && x.head == :call && x.args[1] ∈ whitelist_symbols
    end || return """the provided list has to contain only permitted circuit elements: $(join(map(string,whitelist_symbols),", "))"""
    all(parsed.args) do x
      all(x.args[2:end]) do y
        isa(y, String) || (isa(y, Integer) && y<40) || (isa(y, Expr) && y.head == :vect && all(z->isa(z,Integer)&&z<40,y.args))
      end
    end || return "only Integers smaller than 40, Strings, or lists of Integers may be used as arguments in the construction of a circuit element"
    parsed = postwalk(parsed) do x
      isa(x, String) ? replace(x, r"[^a-zA-Z0-9 +\-*/=_^()]"=>"") : x
    end
    return parsed
  catch e
    if isa(e, Meta.ParseError)
      return "the provided string contains syntax errors: $(e.msg); $(circuitstring)"
    else
      return "unknown parsing error, please report a bug: $(e)"
    end
  end
end

function rendercircuit(warning::String)
  return (false, warning)
end

function rendercircuit(circuitast)
  try
    circuit = eval(circuitast)
    circuitstr = string(circuitast)
    circuituuid = get!(filecache, circuitstr) do
        circuituuid = uuid4()
        f = "$(circuituuid).png"
        savecircuit(circuit, f)
        circuituuid
    end
    f = "$(circuituuid).png"
    data = Base64.base64encode(open(f))
    return (true, """
                  <img src="data:image/png;base64,$(data)">
                  <details>
                  <summary>TeX code for this image</summary>
                  <pre>
                  $(circuit2string(circuit))
                  </pre>
                  </details>
                  """)
  catch e
    return (false, "rendering error: $(repr(e))")
  end
end

route("/") do
  if haskey(@params, :circuit)
    circuit = unescapeuri(replace(@params(:circuit),"+"=>" "))
    parsed = parsecircuit(circuit)
    good, rendered = rendercircuit(parsed)
    if good
      pretty_string = replace(string(parsed),"),"=>"),\n")
      textarea = "$(pretty_string)"
      aboveform = "<p>$(rendered)</p>"
      return TEMPLATE(;textarea,aboveform)
    else
      textarea = "$(circuit)"
      aboveform = "<p>$(rendered)</p>"
      return TEMPLATE(;textarea,aboveform)
    end
  else
    textarea = """
    [CNOT(1,2),
     CPHASE(3,4),
     Measurement(1),
     Measurement("X", 2),
     Measurement("Z", 3, 1)]
    """
    aboveform = ""
    return TEMPLATE(;textarea,aboveform)
  end
end

const TEMPLATE = mt"""
<!doctype html>

<html lang="en">
<head>
  <meta charset="utf-8">

  <title>Quantikz.jl Renderer</title>
  <meta name="description" content="Renderer for quantum circuits.">
  <meta name="author" content="Stefan Krastanov">

<style type="text/css">
body{
  margin:40px auto;
  max-width:650px;
  line-height:1.6;
  font-size:15px;
  color:#444;
  padding:0 10px;
}
h1,h2,h3{
  line-height:1.2;
}
img{
  max-height: 200px;
  max-width: 100%;
  margin: auto;
}
textarea{
  width: 100%;
  height: 10rem;
  margin-top: 1rem;
  margin-bottom: 1rem;
}
iframe{
  width: 100%;
  height: 100vh;
}
pre{
  font-size: 0.8rem;
}
summary{
  font-size: 0.8rem;
}
</style>

<!-- Matomo -->
<script type="text/javascript">
  var _paq = window._paq = window._paq || [];
  /* tracker methods like "setCustomDimension" should be called before "trackPageView" */
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u="//matomo.krastanov.org/";
    _paq.push(['setTrackerUrl', u+'matomo.php']);
    _paq.push(['setSiteId', '3']);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
    g.type='text/javascript'; g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
  })();
</script>
<!-- End Matomo Code -->

</head>

<body>

{{{:aboveform}}}

<form action="/" method="get" id="form">
<textarea name="circuit" form="form">
{{:textarea}}
</textarea> 
<input type="submit" value="Render" onclick="this.form.submit(); this.disabled = true; this.value = 'Rendering...';">
</form>

<p>
Made by <a href="https://blog.krastanov.org">Stefan Krastanov</a> with the <a href="https://github.com/Krastanov/Quantikz">Quantikz.jl</a> Julia library, based on the <a href="https://arxiv.org/abs/1809.03842">Alastair Kay's quantikz TeX package</a>. Runs on <a href="https://www.genieframework.com/">Genie</a>.
</p>

<h2>Accepted Commands (from <a href="https://github.com/Krastanov/Quantikz">Quantikz.jl</a>):</h2>
<iframe src="https://krastanov.github.io/Quantikz/v1.1.0/useful/">
</iframe>

<!-- Matomo Image Tracker-->
<img referrerpolicy="no-referrer-when-downgrade" src="https://matomo.krastanov.org/matomo.php?idsite=3&amp;rec=1" style="border:0" alt="" />
<!-- End Matomo -->

</body>
</html>
"""

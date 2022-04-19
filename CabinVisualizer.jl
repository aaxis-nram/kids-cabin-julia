using YAML
using DelimitedFiles

global kCount, cabins, config

# The Main
function main() 
    global kCount, cabins, config
    
    local configFile = inarg("config","NONE")
    if (configFile==="NONE") 
        println("Usage: julia CabinVisualizer.jl configFile.yaml")
    end
    config = YAML.load_file(configFile)
    kCount = config["kCount"]
    cabins = config["cabins"]

    println("Count: $kCount   Cabins: $cabins")
    # Lets set some global variable
    readData(config["dataFile"])
    
    

end # of main -----------


function readData(dataFile)
    data = readdlm(dataFile, ',', Int64)
    global kPref, kCount
    #println("kCount is $kCount")
    kPref = zeros(Int64,kCount,kCount)
    for kkv in eachrow(data)
        kPref[kkv[1],kkv[2]] = kkv[3]
    end

    #cabinAssignment = zeros(Int64,kCount,3)
    #cabinAssignment[:,2] .= -2    # second col is kid happiness. -2 for not being assigned to a cabin yet
    #kPref = hcat(kPref,cabinAssignment,1:kCount)
end

# For repl debugging
function setup()
    argDict["config"]="config-v1-happyCamper.yaml"
end

function inarg(key, def)
    p = get(argDict,key,nothing)

    if (p===nothing) 
        return def
    elseif (typeof(def)!=typeof("String"))
        return parse(typeof(def),p)
    else 
        return p
    end
end


# The runner 
if abspath(PROGRAM_FILE) == @__FILE__
    # process arguments here
    println("Data Visualizer for kids cabins problem.")
    global argDict = Dict()
    map(arg-> begin
                if !((m=match(r"(\S+)=(\S+)",arg)) === nothing)
                    argDict[m[1]] = m[2]
                else
                    argDict[arg] = true
                end
            end,ARGS )
    main()
else 
    # do this from repl 
    # include("datagen.jl")
    # setup some defaults for REPL testing
    global argDict = Dict()
    argDict["config"] = "config-v1-happyCamper.yaml"
    
    main()
    
    "Loaded."
end
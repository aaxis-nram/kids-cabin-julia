using Distributions, Random
using YAML

# globals
kCount = 25
cabins = 5
kPerCabin = convert(Int64,ceil(kCount/cabins))
dFileName = "data.csv"
setFileName = "set.txt"
argDict = Dict()

# main
function main()
    global kCount, cabins, kPerCabin, dFileName, argDict, chainLength,setFileName

    if (size(ARGS,1)==0)
        println("Usage: julia TestDataGen.jl configFile.yaml")
    end
    configFile = ARGS[1]
    println("TestDataGen v0.01. Config File $configFile")
    config = YAML.load_file(configFile)

    kCount          = config["kCount"]
    cabins          = config["cabins"]
    chainLength     = config["chainLength"]
    avgChainLength  = config["avgChainLength"]
    case            = config["case"]
    dFileName       = config["dataFile"]
    setFileName     = config["setFile"]
    kPerCabin    = convert(Int64,ceil(kCount/cabins))
    
    if (case == "A") 
        generateCaseAData(chainLength)
    elseif (case == "B")
        generateUnevenChainData(avgChainLength, chainLength)
    else 
        println("Case $case unimplemented")
    end
end


# This is generate chains from 1 to maxChainLength
# 1 is a loner
# 2 is a pair
function generateUnevenChainData(avg, max)
    println("Generating Case: B - Normal Chains")
    global kCount, cabins, kPerCabin, dFileName

    # Setup a normal Distributions
    d   = Normal(avg, 1.0)
    td  = truncated(d, 1, max)

    numChains = convert(Int64,ceil(kCount/chainLength))
    
    # open the file
    open(dFileName, "w") do io
    open(setFileName, "w") do sio
        # Generate a set of student numbers
        local karr = sortperm(rand(kCount))
        ka = 0
        snum = 0
        while ka < kCount
            chainLength = convert(Int64,ceil(rand(td)))
            if ka+chainLength > kCount
                chainLength = kCount - ka
            end
            snum += 1
            kt = karr[ka+1:ka+chainLength]
            #println(kt')
            write(sio,"$snum")
            for kti in kt
                write(sio,",$kti")
            end
            write(sio,"\n")
            dima = size(kt,1)
            if (dima==2) 
                write(io, "$(kt[1]),$(kt[2]),2\n")
                write(io, "$(kt[2]),$(kt[1]),2\n")
            else
                for i in 1:dima                                                                                                                               
                    write(io, "$(kt[i]),$(kt[1+i%dima]),2\n")                                                                                                      
                    write(io, "$(kt[i]),$(kt[1+ (i-2+dima)%dima]),2\n")
                end                                                                                            
            end    
            ka += chainLength
        end
        close(sio)
    end # of sio
    close(io)
    end # of io
end  # of generateUnevenChainData

# Happy Campers! this will generate perfect closed rings of cabin size
# last ring will be closed but may be smaller size
function generateCaseAData(chainLength)
    println("Generating Case: A - Happy Campers")
    global kCount, cabins, kPerCabin, dFileName

    numChains = convert(Int64,ceil(kCount/chainLength))
    
    # open the file
    open(dFileName, "w") do io
        # Generate a set of student numbers
        karr = reshape(sortperm(rand(numChains*chainLength)), numChains, chainLength)
        for ks in eachrow(karr)                                                                                                                               
            ks = filter(x->(x <= kCount), ks)                                                                                                             
            dima = size(ks,1)
            if (dima<=2) 
                println("Chain length must be equal to or greater than 3")
                exit()
            end                                                                                                                             
            for i in 1:dima                                                                                                                               
                write(io, string(ks[i]) * "," * string(ks[1+i%dima]) * ",2\n")                                                                                                      
                write(io, string(ks[i]) * "," * string(ks[1+ (i-2+dima)%dima]) * ",2\n")                                                                                            
            end                                                                                                                                           
            #println("-")                                                                                                                                  
        end
    end
    # 
    
    # randomize, create rings
    # output
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
    println("Datagenertor for kids cabins problem.")
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
    push!(ARGS,"config-v1-happyCamper.yaml")

    "Loaded."
end


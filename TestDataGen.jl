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
    global kCount, cabins, kPerCabin, dFileName, argDict, chainLength,setFileName, config

    if (size(ARGS,1)==0)
        println("Usage: julia TestDataGen.jl configFile.yaml")
        exit()
    end
    configFile = ARGS[1]
    println("TestDataGen v0.01. Config File $configFile")
    config = YAML.load_file(configFile)
    case            = config["case"]

    #=
    kCount          = config["kCount"]
    cabins          = config["cabins"]
    chainLength     = config["chainLength"]
    avgChainLength  = config["avgChainLength"]
    dFileName       = config["dataFile"]
    setFileName     = config["setFile"]
    kPerCabin    = convert(Int64,ceil(kCount/cabins))
    =#

    if (case == "A") 
        generateCaseAData(chainLength)
    elseif (case == "B")
        generateUnevenChainData(avgChainLength, chainLength)
    elseif (case == "C")
        generateUnevenChainDataCrossLink(avgChainLength, chainLength)
    elseif (case == "SM")
        generateStableMatch()
    else 
        println("Case $case unimplemented")
    end
end

function generateStableMatch()
    # count of members
    kCount = config["kCount"]
    cabins = config["cabins"]
    kPerCabin       = config["kPerCabin"]
    
    if (kCount/2!=cabins || kPerCabin!=2)
        println("Stable Match requires cabins be equal to half of member.")
        exit(1)
    end

    dFileName       = config["dataFile"]
    setFileName     = config["setFile"]
    allPrefs = []

    open(dFileName, "w") do io
        # 1-kCount/2 are male and kCount/2+1 thru kCount are females
        setPoint = convert(Int64,kCount/2)

        # M Side
        for k=1:setPoint
            pref = setPoint .+ sortperm(rand(setPoint))
            push!(allPrefs, pref)
            weight = setPoint
            for kp in pref
                write(io,"$k,$kp,$weight\n")
                weight -= 1
            end
            for kp in 1:setPoint
                kp!=k && write(io,"$k,$kp,-5\n")
            end
        end

        # W Side
        for k=setPoint+1:kCount
            pref = sortperm(rand(setPoint))
            push!(allPrefs, pref)
            weight = setPoint
            for kp in pref
                write(io,"$k,$kp,$weight\n")
                weight -= 1
            end
            for kp in setPoint+1:kCount
                kp!=k && write(io,"$k,$kp,-5\n")
            end
        end
    end
    
    open(setFileName, "w") do sio
        write(sio,"For Python\n")
        for pref in allPrefs        
            write(sio, "[" * join(pref .- 1,",") * "],\n") 
        end
        write(sio, "\nFor Julia\n" )
        for pref in allPrefs
            write(sio, "[" * join(pref,",") * "],\n") 
        end
    end

    
end



# This is generate chains from 1 to maxChainLength
# 1 is a loner
# 2 is a pair
function generateUnevenChainDataCrossLink(avg, max)
    println("Generating Case: C - Chains with crosslinks")
    global kCount, cabins, kPerCabin, dFileName

    local sd = config["sd"]
    # Setup a normal Distributions
    d   = Normal(avg, sd)
    td  = truncated(d, 1, max)

    numChains = convert(Int64,ceil(kCount/chainLength))
    maxCrossLink = convert(Int64,floor(kPerCabin/2))

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
            kt = sort(karr[ka+1:ka+chainLength])
            #println(kt')
            write(sio,"$snum")
            for kti in kt
                write(sio,",$kti")
            end
            write(sio,"\n")
            dima = size(kt,1)
            
            if (dima==2) 
                write(io, "$(kt[1]),$(kt[2]),5\n")
                write(io, "$(kt[2]),$(kt[1]),5\n")
            else
                for i in 1:dima                                                                                                                               
                    write(io, "$(kt[i]),$(kt[1+i%dima]),5\n")                                                                                                      
                    write(io, "$(kt[i]),$(kt[1+ (i-2+dima)%dima]),5\n")
                    # some cross links
                    randKt = kt[sortperm(rand(size(kt,1)))]
                    
                    csCount = 0
                    for kj in randKt
                        if (kj != kt[i] && kj != kt[1+i%dima] && kj != kt[1+ (i-2+dima)%dima])
                            csCount+=1
                            write(io, "$(kt[i]),$kj,1\n")
                            if (csCount>=maxCrossLink)
                                break
                            end
                        end
                    end
                end
            end    
            ka += chainLength
        end
        close(sio)
    end # of sio
    close(io)
    end # of io
end  # of generateUnevenChainData

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
    # just call main
    main()
else 
    # do this from repl 
    # include("datagen.jl")
    # setup some defaults for REPL testing
    push!(ARGS,"config-v1-happyCamper.yaml")

    "Loaded."
end


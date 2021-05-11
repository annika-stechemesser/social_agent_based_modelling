using Agents
using Statistics
using InteractiveDynamics
using GLMakie

@agent homoOeconomicus GridAgent{2} begin
    kilometersPerYear::Float64
    vehicle::Int # very primitive state variable: 1 = combustion engine, 2 = electric vehicle (TBextended by 0= no car)
    vehicleValue::Float64 # current time value
    purchaseValue::Float64
    vehicleAge::Int
    budget::Float64
end

function modelHomoOeconomicus(
    space = Agents.GridSpace((10, 10); periodic = false, metric = :euclidean);
    numagents = 100,
    priceCombustionVehicle = 10000,
    priceElectricVehicle = 20000,
    fuelCostKM = 0.1,
    powerCostKM = 0.05,
    maintenanceCostCombustionKM = 0.005,
    maintenanceCostElectricKM = 0.01,
    usedVehicleDiscount::Float64 = 0.8, #assumption: loss of 20% of vehicle value due to used vehicle market conditions
    budget = 1000000 # for now only dummy implementation
)
    model = ABM(
        homoOeconomicus,
        space,
        scheduler = Agents.Schedulers.fastest,
        properties = Dict(
            :priceCombustionVehicle => priceCombustionVehicle,
            :priceElectricVehicle => priceElectricVehicle,
            :fuelCostKM => fuelCostKM,
            :powerCostKM => powerCostKM,
            :maintenanceCostCombustionKM => maintenanceCostCombustionKM,
            :maintenanceCostElectricKM => maintenanceCostElectricKM,
            :usedVehicleDiscount => usedVehicleDiscount,
            :budget => budget # assumtpion for now: uniform budget
        ),
    )
    for i = 1:numagents
        kilometersPerYear = 15000 + (7500 * (rand(model.rng) - 0.5)) #  diverse population with different millages
        initialVehicle = 1 # population of combustion engine owners
        initialValue = 0.0
        if initialVehicle == 1
            initialValue = priceCombustionVehicle
        end
        if initialVehicle == 2
            initialValue = priceElectricVehicle
        end
        add_agent_single!(
            model,
            kilometersPerYear,
            initialVehicle,
            initialValue,
            initialValue,
            0,
            budget
        )
    end
    return model
end

function yearlyVehicleCost(
    yrlyKilometers::Float64,
    vehicleAge,
    vehicle,
    model
)
    fuelCostKM = vehicle == 1 ? model.fuelCostKM : model.powerCostKM
    maintenanceCostKM = vehicle == 1 ? model.maintenanceCostCombustionKM : model.maintenanceCostElectricKM
    return yrlyKilometers * (fuelCostKM +  maintenanceCostKM * vehicleAge)
end

function depreciateVehicleValue(purchaseValue, vehicleAge, feasibleYears)
    return purchaseValue - vehicleAge / feasibleYears * purchaseValue # very simple linear depreciation
end

function agent_step!(agent, model)
    agent.vehicleAge = agent.vehicleAge + 1
    #assumption: all vehicles are assumed to last at least 300.000km before purchase of a new vehicle
    feasibleYears = cld(300000, agent.kilometersPerYear) # rounding up division
    #calculate cost of current car vs. a new car:
    currentCost = 0.0
    newCombustionCost = 0.0
    newElectricCost = 0.0
    for i_year in 1:(feasibleYears-agent.vehicleAge)
            currentCost += yearlyVehicleCost(
                agent.kilometersPerYear,
                agent.vehicleAge + i_year,
                agent.vehicle,
                model
            )
    end
    for i_year in 1:feasibleYears
        newCombustionCost += yearlyVehicleCost(
            agent.kilometersPerYear,
            i_year,
            1,
            model
        )
        newElectricCost += yearlyVehicleCost(
            agent.kilometersPerYear,
            i_year,
            2,
            model
        )
    end
    #purchasing cost after selling old car
    incomeSellingOldVehicle = agent.vehicleValue*model.usedVehicleDiscount
    newCombustionPurchase = model.priceCombustionVehicle - incomeSellingOldVehicle
    newElectricPurchase = model.priceElectricVehicle - incomeSellingOldVehicle
    # compare average cost
    if (agent.vehicleAge<feasibleYears)
        currentVehicleAverageCost =
            (currentCost) / (feasibleYears - agent.vehicleAge)
    else
        currentVehicleAverageCost = 1000000 # dummy implementation to enforce buying a new car at the end of useage time
    end
    newCombustionAverageCost =
        (newCombustionCost + newCombustionPurchase) / feasibleYears
    newElectricAverageCost =
        (newElectricCost + newElectricPurchase) / feasibleYears
    #make decision and update vehicle attributes
    new_vehicle = false # dummy variable
    if (
        min(newCombustionAverageCost, newElectricAverageCost) <
        currentVehicleAverageCost
    )
        if (newCombustionAverageCost < newElectricAverageCost)
            if (newCombustionPurchase<=agent.budget)
                agent.vehicle = 1
                agent.vehicleValue = model.priceCombustionVehicle
                agent.purchaseValue = model.priceCombustionVehicle
                agent.vehicleAge = 0
                new_vehicle=true
            end
        else
            if (newCombustionPurchase<=agent.budget)
                agent.vehicle = 2
                agent.vehicleValue = model.priceElectricVehicle
                agent.purchaseValue = model.priceElectricVehicle
                agent.vehicleAge = 0
                new_vehicle=true
            end
        end
    end
    if new_vehicle==false
        agent.vehicleValue = depreciateVehicleValue(
            agent.purchaseValue,
            agent.vehicleAge,
            feasibleYears,
        )
    end
end

function model_step!(model)
    for a in allagents(model)
        rand(model.rng) # dummy function since no model updated implemented ATM
    end
end


gaiaOeconomicus = modelHomoOeconomicus()

Agents.step!(gaiaOeconomicus, agent_step!, model_step!, 1)


parange = Dict(
    :priceCombustionVehicle => 5000:100000,
    :priceElectricVehicle => 5000:100000,
    :fuelCostKM => range(0.05, 0.5; step = 0.025),
    :powerCostKM => range(0.05, 0.5; step = 0.025),
)

adata = [(:vehicleValue, mean), (:vehicle, mean), (:vehicleAge, mean)]
alabels = ["vehicleValue", "avg. vehicle", "avg. vehicle age"]

vehiclecolor(a) = a.vehicle == 1 ? :orange : :blue
vehiclemarker(a) = a.vehicle == 1 ? :circle : :rect

scene, adf, modeldf = abm_data_exploration(
    gaiaOeconomicus,
    agent_step!,
    model_step!,
    parange;
    ac = vehiclecolor,
    am = vehiclemarker,
    as = 4,
    adata = adata,
    alabels = alabels,
)

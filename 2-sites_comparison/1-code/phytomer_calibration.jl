using XPalmModel
using XPalmModel.PlantMeteo
using PlantSimEngine
using DataFrames, CSV, YAML
using CairoMakie, AlgebraOfGraphics

meteo = CSV.read("0-data/Meteo_predictions_all_sites_cleaned.csv", DataFrame)
meteos = [Weather(i) for i in groupby(meteo, :Site)]

# Import the mapping:
includet("mapping.jl")

# Make a simulation:
begin
    params_default = YAML.load_file("0-data/xpalm_parameters_new2.yml", dicttype=Dict{Symbol,Any})

    params_SMSE = copy(params_default)
    params_SMSE[:latitude] = 2.93416
    params_SMSE[:altitude] = 15.5

    params_PRESCO = copy(params_default)
    params_PRESCO[:latitude] = 6.137
    params_PRESCO[:altitude] = 15.5

    params_TOWE = copy(params_default)
    # params_TOWE[:latitude] = 7.65
    params_TOWE[:latitude] = 7.00
    params_TOWE[:altitude] = 15.5

    params = Dict("SMSE" => params_SMSE, "PR" => params_PRESCO, "TOWE" => params_TOWE,)
    out_vars = Dict{String,Any}("Plant" => (:TEff, :plant_age, :ftsw, :phytomer_count,),)

    simulations = DataFrame[]
    for m in meteos
        # m = meteos[1]
        site = m[1].Site
        palm = XPalmModel.Palm(initiation_age=0, parameters=params[site])
        sim = XPalmModel.PlantSimEngine.run!(palm.mtg, xpalm_mapping(palm), m, outputs=out_vars, executor=XPalmModel.PlantSimEngine.SequentialEx(), check=false)
        df = XPalmModel.PlantSimEngine.outputs(sim, DataFrame, no_value=missing)
        df[!, "Site"] .= site
        push!(simulations, df)
    end

    # Adding the dates to the simulations:
    dfs_all = vcat(simulations...)
    dfs_all = leftjoin(dfs_all, meteo, on=[:Site, :timestep,])
    sort!(dfs_all, [:Site, :timestep])
end

dfs_plant = filter(row -> row[:organ] == "Plant", dfs_all)

function phytomer_emergence(plant_age, TEff, ftsw; threshold_ftsw_stress=0.3, production_speed_initial=0.0111, production_speed_mature=0.0074)
    production_speed = XPalmModel.age_relative_value.(
        plant_age,
        0.0,
        2920,
        production_speed_initial,
        production_speed_mature
    )

    phylo_slow = [f > threshold_ftsw_stress ? 1.0 : f / threshold_ftsw_stress for f in ftsw]

    phytomers = zeros(length(TEff))
    phytomer_i = 1
    newPhytomerEmergence = 0.0
    for i in eachindex(phylo_slow)
        newPhytomerEmergence += TEff[i] * production_speed[i] * phylo_slow[i]

        if newPhytomerEmergence >= 1.0
            newPhytomerEmergence -= 1.0
            phytomer_i += 1
        end

        phytomers[i] = phytomer_i
    end
    return phytomers
end


df_out = transform(
    groupby(dfs_plant, :Site),
    [:plant_age, :TEff, :ftsw] => ((x, y, z) -> phytomer_emergence(x, y, z)) => :phytomer_emergence_custom
)

data(df_out) * mapping(:months_after_planting, :phytomer_emergence_custom => "Phytomer emergence", color=:Site => nonnumeric) * visual(Scatter) |> draw()


df_plant_SMSE = filter(row -> row[:Site] == "SMSE", dfs_plant)
begin
    f, ax, p = lines(df_plant_SMSE.months_after_planting, phytomer_emergence(df_plant_SMSE.plant_age, df_plant_SMSE.TEff, df_plant_SMSE.ftsw))
    lines!(ax, df_plant_SMSE.months_after_planting, [df_plant_SMSE.phytomer_count...], color=:red)
    lines!(ax, df_plant_SMSE.months_after_planting, phytomer_emergence(df_plant_SMSE.plant_age, df_plant_SMSE.TEff, df_plant_SMSE.ftsw, production_speed_initial=0.0050, production_speed_mature=0.0040), color=:green)
    f
end
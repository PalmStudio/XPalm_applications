using XPalmModel, CSV, DataFrames, YAML
using CairoMakie, AlgebraOfGraphics
using XPalmModel.PlantMeteo
using Dates
using Statistics

meteo = Weather(CSV.read("0-data/Meteo_Indonesia_SMSE.txt", DataFrame))
params = YAML.load_file("0-data/xpalm_parameters.yml", dicttype=Dict{Symbol,Any})

out_vars = Dict{String,Any}(
    "Scene" => (:lai,),
    # "Scene" => (:lai, :scene_leaf_area, :aPPFD, :TEff),
    # "Plant" => (:plant_age, :ftsw, :newPhytomerEmergence, :aPPFD, :plant_leaf_area, :carbon_assimilation, :carbon_offer_after_rm, :Rm, :TT_since_init, :TEff, :phytomer_count, :newPhytomerEmergence),
    # "Leaf" => (:Rm, :potential_area, :TT_since_init, :TEff, :A, :carbon_demand, :carbon_allocation,),
    "Phytomer" => (:rank, :state),
    "Leaf" => (:Rm, :TEff, :TT_since_init, :potential_area, :carbon_demand, :carbon_allocation, :biomass, :final_potential_area, :increment_potential_area, :initiation_age, :leaf_area, :reserve, :rank, :leaf_state),
    "Internode" => (
        :Rm, :carbon_allocation, :carbon_demand, :potential_height, :potential_radius, :potential_volume, :biomass, :reserve,
        :final_potential_height, :final_potential_radius, :initiation_age, :TT_since_init, :final_potential_height, :final_potential_radius
    ),
    "Male" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :final_potential_biomass, :TEff),
    "Female" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :TEff, :fruits_number, :state,),
    "Plant" => (
        :biomass_bunch_harvested, :Rm, :aPPFD, :carbon_allocation, :biomass_bunch_harvested, :biomass_fruit_harvested,
        :carbon_assimilation, :reserve, :carbon_demand, :carbon_offer_after_allocation, :carbon_offer_after_rm, :plant_leaf_area,
        :n_bunches_harvested, :biomass_bunch_harvested_cum, :n_bunches_harvested_cum
    ),
    # "Soil" => (:TEff, :ftsw, :root_depth),
)

palm = XPalmModel.Palm(initiation_age=0, parameters=XPalmModel.default_parameters())
@time sim = XPalmModel.PlantSimEngine.run!(palm.mtg, XPalmModel.model_mapping(palm), meteo, outputs=out_vars, executor=XPalmModel.PlantSimEngine.SequentialEx(), check=false);
# 6.5s
@time df = XPalmModel.PlantSimEngine.outputs(sim, DataFrame, no_value=missing)

df_phytomer = filter(row -> row[:organ] == "Phytomer", df)
scatter(df_phytomer.timestep, df_phytomer.rank, color=:green, markersize=3)

filter(row -> row.node == 6, df_phytomer) |>
(x -> data(x) * mapping(:timestep, :rank, color=:node => nonnumeric) * visual(Lines)) |>
draw()

scatter(filter(x -> x.node == 699, df_phytomer).rank)
print(filter(x -> x.node == 699, df_phytomer).rank)

df_scene = filter(row -> row[:organ] == "Scene", df)
df_scene.date = meteo.date
df_scene.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_scene.date]
# Computes the index of the month since the beginning of the simulation:
df_scene.months_after_planting = groupindices(groupby(df_scene, :yearmonth))

scatter(df_scene.timestep, df_scene.lai, color=:green, markersize=3)
maximum(df_scene.lai)

scatter(df_scene.lai[365*10:min(365 * 12, length(df_scene.lai))])

df_plant = filter(row -> row[:organ] == "Plant", df)
df_plant.date = meteo.date
df_plant.yearmonth = [Date(Dates.yearmonth(d)...) for d in df_plant.date]
# Computes the index of the month since the beginning of the simulation:
df_plant.months_after_planting = groupindices(groupby(df_plant, :yearmonth))

scatter(df_plant.timestep, df_plant.plant_leaf_area, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.aPPFD, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_assimilation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.Rm, color=:green, markersize=3)

scatter(df_plant.timestep, df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_allocation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.reserve, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_allocation, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_rm, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.carbon_offer_after_rm - df_plant.carbon_demand, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.Rm ./ df_plant.carbon_assimilation, color=:green, markersize=3)
scatter(df_plant.date, df_plant.biomass_bunch_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.biomass_fruit_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.n_bunches_harvested, color=:green, markersize=3)
scatter(df_plant.timestep, df_plant.biomass_bunch_harvested_cum, color=:green, markersize=3)

# Monthly harvest:
df_scene_month = combine(groupby(df_scene, :yearmonth), :lai => mean => :lai, :months_after_planting => unique => :months_after_planting)
df_plant_month = combine(groupby(df_plant, :yearmonth), :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly, :months_after_planting => unique => :months_after_planting)
CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
# Monthly harvest in kg dry mass per plant:
lines(df_plant_month.yearmonth, df_plant_month.biomass_bunch_harvested_monthly ./ 1000 ./ CC_Fruit, color=:black)
lines(df_plant_month.months_after_planting, df_plant_month.biomass_bunch_harvested_monthly ./ 1000 ./ CC_Fruit, color=:black)
lines(df_scene_month.months_after_planting, df_scene_month.lai, color=:black)

df_internode = filter(row -> row[:organ] == "Internode", df)
df_internode_7 = filter(row -> row[:node] == 7, df_internode)
df_internode_one = filter(row -> row[:node] == 852, df_internode)

scatter(df_internode_7.carbon_demand)
scatter(df_internode_7.Rm)
scatter(df_internode_7.biomass)
sum(df_internode_7.carbon_demand)
df_internode_7.TT_since_init[1]
df_internode_7.initiation_age[1]
df_internode_7.reserve[1]
df_internode_7.biomass[1]


combine(groupby(df_internode, :timestep), :carbon_demand => sum)

reserves_trunk = combine(groupby(df_internode, :timestep), :reserve => sum) ./ 1000
lines(reserves_trunk.reserve_sum)
lines(reserves_trunk[365*10:min(365 * 12, nrow(reserves_trunk)), :].reserve_sum)



scatter(df_internode_one.timestep, df_internode_one.potential_height, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.potential_radius, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.potential_volume, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.carbon_demand, color=:green, markersize=3)
sum(df_internode_one.carbon_demand)
scatter(df_internode_one.timestep, df_internode_one.carbon_allocation, color=:green, markersize=3)
scatter(df_internode_one.timestep, df_internode_one.biomass .* 0.0017950000000000002, color=:green, markersize=3)
scatter(df_internode_one.Rm[2:end], color=:green, markersize=3)


df_leaf = filter(row -> row[:organ] == "Leaf", df)

# Count the number of occurence of each leaf state:
combine(groupby(filter(row -> row.timestep == 4291, df_leaf), :leaf_state), :leaf_state => length)

filter(row -> row.timestep == 4291, df_leaf)
sum(filter(row -> row.timestep == 4291, df_leaf).leaf_area)

sum(filter(row -> row.timestep == 4291 && row.leaf_state == "undetermined", df_leaf).leaf_area)

sum(filter(row -> row.timestep == 2190, df_leaf).leaf_area)
df_plant.plant_leaf_area[1460]


df_leaf_8 = filter(row -> row[:node] == 8, df_leaf)
scatter(df_leaf_8.carbon_demand)
scatter(df_leaf_8.rank)
df_leaf_8.reserve

df_leaf_one = filter(row -> row[:node] == 853, df_leaf)
scatter(df_leaf_one.timestep, df_leaf_one.final_potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.increment_potential_area, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.carbon_demand, color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.carbon_allocation, color=:green, markersize=3)
scatter(df_leaf_one.timestep, [df_leaf_one.leaf_area...], color=:green, markersize=3)
scatter(df_leaf_one.timestep, df_leaf_one.biomass, color=:green, markersize=3)
f, a, plt = scatter(df_leaf_one.timestep, df_leaf_one.reserve, color=:green, markersize=3)
scatter!(a, df_leaf_one.timestep, df_leaf_one.biomass, markersize=3)
f

df_male = filter(row -> row[:organ] == "Male", df)
df_male_1 = filter(row -> row[:node] == 193, df_male)

scatter(df_male_1.timestep, df_male_1.TEff, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.final_potential_biomass, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.carbon_demand, color=:green, markersize=3)
scatter(df_male_1.timestep, df_male_1.carbon_allocation, color=:green, markersize=3)

df_female = filter(row -> row[:organ] == "Female", df)
df_female_1 = filter(row -> row[:node] == 189, df_female)
scatter(df_female_1.timestep, df_female_1.carbon_demand, color=:green, markersize=3)
scatter(df_female_1.timestep, df_female_1.carbon_allocation, color=:green, markersize=3)

df_female_other = filter(row -> row[:node] == 858, df_female)
scatter(df_female_other.timestep, df_female_other.carbon_demand, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.carbon_allocation, color=:green, markersize=3)
scatter(df_female_other.timestep, df_female_other.biomass, color=:green, markersize=3)
sum(df_female_other.carbon_demand)


# Using a notebook instead:
using Pluto, XPalmModel
XPalmModel.notebook("xpalm_notebook.jl")


#! To remove:
# Read the parameters from a YAML file (provided in the example folder of the package):
using YAML
parameters = YAML.load_file(joinpath(dirname(dirname(pathof(XPalmModel))), "examples/xpalm_parameters.yml"); dicttype=Dict{Symbol,Any})

# Create palm with custom parameters
p = XPalmModel.Palm(parameters=parameters)

# Run simulation with multiple outputs
results = xpalm(
    meteo,
    DataFrame,
    vars=Dict(
        "Scene" => (:lai,),
        "Plant" => (:leaf_area, :biomass_bunch_harvested),
        "Soil" => (:ftsw,)
    ),
    palm=p,
)
using XPalm, CSV, DataFrames, YAML
using CairoMakie, AlgebraOfGraphics
import PlantSimEngine: MultiScaleModel, PreviousTimeStep
using XPalm.Models
using PlantMeteo
using Dates
using Statistics

cd(@__DIR__)
include("mapping.jl")

meteo = CSV.read(joinpath(@__DIR__, "../0-data/Meteo_predictions_all_sites_cleaned.csv"), DataFrame)
meteos = [Weather(i) for i in groupby(meteo, :Site)]

df_plot = transform(groupby(meteo, :Site), :Precipitations => cumsum => :cumulative_precipitations, :Tmin => cumsum => :Tmin_cumulative, :Tmax => cumsum => :Tmax_cumulative)
data(df_plot) * mapping(:date, :Precipitations, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :cumulative_precipitations, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :Tmin_cumulative, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_plot) * mapping(:date, :Tmax_cumulative, color=:Site => nonnumeric) * visual(Lines) |> draw()

begin
    params_default = YAML.load_file(joinpath(@__DIR__, "../0-data/xpalm_parameters.yml"))

    params_SMSE = copy(params_default)
    params_SMSE["plot"]["latitude"] = 2.93416
    params_SMSE["plot"]["altitude"] = 15.5

    params_PRESCO = copy(params_default)
    params_PRESCO["plot"]["latitude"] = 6.137
    params_PRESCO["plot"]["altitude"] = 15.5

    params_TOWE = copy(params_default)
    # params_TOWE[:latitude] = 7.65
    params_TOWE["plot"]["latitude"] = 7.00 #! check why we can't use the true value in XPalm
    params_TOWE["plot"]["altitude"] = 15.5

    params = Dict("SMSE" => params_SMSE, "PR" => params_PRESCO, "TOWE" => params_TOWE,)

    out_vars = Dict{String,Any}(
        "Scene" => (:lai, :aPPFD),
        "Phytomer" => (:state, :TEff, :TT_since_init),
        "Leaf" => (
            :Rm, :TEff, :TT_since_init, :maturity, :potential_area, :carbon_demand, :carbon_allocation, :biomass, :final_potential_area,
            :increment_potential_area, :initiation_age, :leaf_area, :reserve, :rank, :state, :pruning_decision
        ),
        "Internode" => (
            :Rm, :carbon_allocation, :carbon_demand, :potential_height, :potential_radius, :potential_volume, :biomass, :reserve,
            :final_potential_height, :final_potential_radius, :initiation_age, :TT_since_init, :final_potential_height, :final_potential_radius,
            :height, :radius,
        ),
        "Male" => (:Rm, :carbon_demand, :carbon_allocation, :biomass, :final_potential_biomass, :TEff, :state),
        "Female" => (
            :Rm, :carbon_demand, :carbon_allocation, :biomass, :TEff, :fruits_number, :state, :carbon_demand_non_oil, :carbon_demand_oil, :carbon_demand_stalk, :biomass_fruits,
            :biomass_stalk, :TT_since_init, :biomass_bunch_harvested
        ),
        "Plant" => (
            :TEff, :plant_age, :ftsw, :Rm, :aPPFD, :carbon_allocation, :biomass_bunch_harvested, :biomass_fruit_harvested,
            :carbon_assimilation, :reserve, :carbon_demand, :carbon_offer_after_allocation, :carbon_offer_after_rm, :leaf_area,
            :n_bunches_harvested, :biomass_bunch_harvested_cum, :n_bunches_harvested_cum, :TEff, :phytomer_count, :production_speed,
        ),
        # "RootSystem" => (:Rm,),
        "Soil" => (:ftsw, :root_depth, :transpiration, :qty_H2O_C1, :qty_H2O_C2, :aPPFD),
    )

    simulations = Dict{String,DataFrame}[]
    for m in meteos
        site = m[1].Site
        palm = XPalm.Palm(parameters=params[site])
        df = xpalm(m, DataFrame, vars=out_vars, palm=palm)
        for (k, v) in df
            v[!, "Site"] .= site
        end
        push!(simulations, df)
    end
end

#! Scene scale
df_scene = vcat([s["Scene"] for s in simulations]...)
df_scene = leftjoin(df_scene, meteo, on=[:Site, :timestep])
sort!(df_scene, [:Site, :timestep])

dfs_scene_months = combine(groupby(df_scene, [:Site, :months_after_planting]), :lai => mean => :lai)
p_lai = data(dfs_scene_months) * mapping(:months_after_planting, :lai, color=:Site => nonnumeric) * visual(Lines)
draw(p_lai)

data(df_scene) * mapping(:timestep, :aPPFD => "Absorbed PPFD (MJ m⁻²[soil] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Plant scale
dfs_plant = vcat([s["Plant"] for s in simulations]...)
dfs_plant = leftjoin(dfs_plant, meteo, on=[:Site, :timestep])
sort!(dfs_plant, [:Site, :timestep])

# combine(groupby(dfs_plant, :Site), :TEff => sum => :TEff)

dfs_plant_month = combine(
    groupby(dfs_plant, [:Site, :months_after_planting]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :TEff => sum => :TEff,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly,
    :biomass_bunch_harvested_cum => last => :biomass_bunch_harvested_cum,
    :n_bunches_harvested => sum => :n_bunches_harvested_monthly,
    :n_bunches_harvested_cum => last => :n_bunches_harvested_cum,
    :phytomer_count => last => :phytomer_count,
    :phytomer_count => (x -> x[end] - x[1]) => :phytomer_emmitted,
)

dfs_plant_year = combine(
    groupby(transform(dfs_plant, :date => ByRow(year) => :year), [:Site, :year]),
    :TEff => sum => :TEff,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested,
)

data(dfs_plant_month) * mapping(:months_after_planting, :phytomer_emmitted, color=:Site => nonnumeric) * visual(Lines) |> draw()

# Observations of emitted leaves:
nb_leaves_emitted_obs = CSV.read(joinpath(@__DIR__, "../0-data/validation/phyllochron_observations.csv"), DataFrame)
sort!(nb_leaves_emitted_obs, [:site, :genotype, :months_after_planting])
transform!(groupby(nb_leaves_emitted_obs, [:site, :genotype]), :nb_leaves_emitted => cumsum => :nb_leaves_emitted_cum)

nb_leaves_emitted_obs = leftjoin(nb_leaves_emitted_obs, select(dfs_plant_month, :Site, :date, :TEff, :phytomer_emmitted => :nb_leaves_emitted_sim), on=[:site => :Site, :date])
dropmissing!(nb_leaves_emitted_obs)
transform!(groupby(nb_leaves_emitted_obs, [:site, :genotype]), :nb_leaves_emitted_sim => cumsum => :nb_leaves_emitted_cum_sim, [:nb_leaves_emitted, :TEff] => ((x, y) -> x ./ y) => :nb_leaves_emitted_per_TEff)

data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_cum, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_per_TEff, color=:genotype, layout=:site) * visual(Lines) |> draw()
# data(nb_leaves_emitted_obs) * mapping(:months_after_planting, :nb_leaves_emitted_cum_sim, color=:genotype, layout=:site) * visual(Lines) |> draw()
data(nb_leaves_emitted_obs) * mapping(:months_after_planting, (:nb_leaves_emitted, :TEff) => ((x, y) -> x / y) => "nb_leaves_emitted_per_TEff", color=:site) * visual(Scatter) |> draw()

#! Computing the phyllochron (production speed) for each site at 50 and 100MAP:
phylochron_MAP50 = combine(groupby(filter(row -> row.months_after_planting < 50, nb_leaves_emitted_obs), :site), :nb_leaves_emitted_per_TEff => mean => :nb_leaves_emitted_per_TEff)
phylochron_MAP100 = combine(groupby(filter(row -> row.months_after_planting > 100, nb_leaves_emitted_obs), :site), :nb_leaves_emitted_per_TEff => mean => :nb_leaves_emitted_per_TEff)
# Computing the average over all sites, that we use in the parameter file.
mean(phylochron_MAP50.nb_leaves_emitted_per_TEff), mean(phylochron_MAP100.nb_leaves_emitted_per_TEff)
#! note: the phyllochron seems to be affected by stress, as it is lower in SMSE and even lower in TOWE compared to PR.

# Computing the number of leaves emitted between 50 and 100MAP:
leaves_emitted_50MAP_100MAP = leftjoin(
    filter(row -> row.months_after_planting == 50, nb_leaves_emitted_obs),
    filter(row -> row.months_after_planting == 100, nb_leaves_emitted_obs),
    on=[:site, :genotype], renamecols="_50MAP" => "_100MAP"
) |> dropmissing!
nb_leaves_50_to_100MAP_obs = leaves_emitted_50MAP_100MAP.nb_leaves_emitted_cum_100MAP .- leaves_emitted_50MAP_100MAP.nb_leaves_emitted_cum_50MAP


df_phytomer_count = combine(groupby(dfs_plant_month, :Site), :months_after_planting => last, :phytomer_count => maximum, :TEff => sum, :nb_timesteps => sum, renamecols=false)
df_phytomer_count.phytomer_per_TT = df_phytomer_count.phytomer_count ./ df_phytomer_count.TEff
df_phytomer_count.phytomer_per_day = df_phytomer_count.phytomer_count ./ df_phytomer_count.nb_timesteps
df_phytomer_count.days_per_phytomer = df_phytomer_count.nb_timesteps ./ df_phytomer_count.phytomer_count

data(dfs_plant) * mapping(:timestep, :carbon_assimilation, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :aPPFD => "Absorbed PPFD (mol[PAR] plant⁻¹ d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, (:aPPFD, :leaf_area) => ((x, y) -> x / y) => "Absorbed PPFD (mol[PAR] m⁻²[leaf] d⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant) * mapping(:timestep, :leaf_area, color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :Rm) => ((x, y) -> y / x) => "Respiration Factor", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_assimilation, :leaf_area) => ((x, y) -> y / x) => "A (gc m-2 leaf)", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 3000, dfs_plant)) * mapping(:timestep, (:carbon_offer_after_rm, :carbon_demand) => ((x, y) -> x / y) => "Trophic state", color=:Site => nonnumeric) * visual(Lines) |> draw()

data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_offer_after_rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Carbon reserve, should be around 80kg at 10-12 years old:
data(filter(row -> row.timestep > 100, dfs_plant)) * mapping(:timestep, :reserve => (x -> x * 1e-3), color=:Site => nonnumeric) * visual(Lines) |> draw()

CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
water_content_mesocarp = 0.25  # Water content of the mesocarp
dry_to_fresh_ratio = 1 / (1 - water_content_mesocarp)  # Based on the mesocarp water content of 0.3

# Monthly harvest in kg dry mass per plant:
data(dfs_plant) * mapping(:timestep, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Bunch Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! should be around 10kg for TOWE, 15-20kg for PR and 20kg for SMSE at 150MAP
data(dfs_plant) * mapping(:timestep, :biomass_fruit_harvested => (x -> x * 1e-3 / CC_Fruit) => "Biomass Fruit Harvested (kg dry mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

# Monthly harvest in kg fresh mass per plant (assuming 30% water content):
data(dfs_plant) * mapping(:months_after_planting, :biomass_bunch_harvested_cum => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
#! should be around 500 for TOWE, 1000 for PR and 1500 for SMSE at 150MAP

data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_monthly, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Should be around 80-150 at 150 months after planting, 50-80 for TOWE
data(dfs_plant_month) * mapping(:months_after_planting, :n_bunches_harvested_cum, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! this is a good one!! It should be around 100kg for PR, 750 for SMSE and 250 for TOWE at 100 MAP
p_ffb = data(dfs_plant_month) * mapping(:months_after_planting, :biomass_bunch_harvested_cum => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "Cumulated FFB (kg tree⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
# save("2-output/FFB_cumulated.png", p_ffb)

#! FFB in kg plant-1 year-1 should be around 100-200 kg according to Van Kraalingen et al. 1989 (may be way higher now):
p_ffb_year_plant = data(dfs_plant_year) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "FFB (kg plant⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()
#! FFB (yield, t ha-1):
p_ffb_year_plot = data(dfs_plant_year) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / params_default["plot"]["scene_area"] * 10000) => "FFB (t ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()


p_ffb_year_plant = data(sort(dfs_plant_year, :year)) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "FFB (kg plant⁻¹ year⁻¹)") * visual(Lines) |> draw()
p_ffb_year_plot = data(sort(dfs_plant_year, :year)) * mapping(:year, :biomass_bunch_harvested => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / params_default["plot"]["scene_area"] * 10000) => "FFB (t ha⁻¹ year⁻¹)") * visual(Lines) |> draw()


dfs_soil = vcat([s["Soil"] for s in simulations]...)
dfs_soil = leftjoin(dfs_soil, meteo, on=[:Site, :timestep])
sort!(dfs_soil, [:Site, :timestep])

data(dfs_soil) * mapping(:timestep, :ftsw, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :transpiration, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :root_depth, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C1, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(dfs_soil) * mapping(:timestep, :qty_H2O_C2, color=:Site => nonnumeric) * visual(Lines) |> draw()

#! Females (bunches)
df_female = vcat([s["Female"] for s in simulations]...)
df_female = leftjoin(df_female, meteo, on=[:Site, :timestep])
sort!(df_female, [:Site, :timestep])

df_female_month = combine(
    groupby(df_female, [:Site, :months_after_planting]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :state => (x -> sum(x .== "Harvested")) => :n_bunches_harvested,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested,
    :biomass_bunch_harvested => (x -> mean(filter(y -> y > 0, x))) => :biomass_bunch_harvested_average,
)

#! Average bunch biomass:
data(df_female_month) * mapping(:months_after_planting, :biomass_bunch_harvested_average => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Average bunch biomass (kg)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! number of fruits per bunch:
data(df_female) * mapping(:timestep, :fruits_number => (x -> x > 0 ? x : 0) => "Number of fruits", color=:Site => nonnumeric, marker=:node => nonnumeric) * visual(Scatter) |> draw()

#! Calibration of the number of fruits:
days_increase_number_fruits = 2379.0
days_maximum_number_fruits = 6500.0
potential_fruit_number_at_maturity = 2000
fraction_first_female = 0.3
coeff = XPalm.age_relative_value.(1:length(meteos[1]), days_increase_number_fruits, days_maximum_number_fruits, fraction_first_female, 1.0)
data(DataFrame(months_after_planting=meteos[1].months_after_planting, nfruits=coeff .* potential_fruit_number_at_maturity)) * mapping(:months_after_planting, :nfruits) * visual(Lines) |> draw()
#! it should be around 600 at 50 MAP, then increasing to 1000 at 100MAP (and 2000 at 150MAP) (see PR site in CIGE data)

df_female_1 = subset(df_female, :node => (x -> x .== 973))
data(df_female_1) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_fruits, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :biomass_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_female_1) * mapping(:timestep, :carbon_demand_non_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_oil, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_demand_stalk, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :fruits_number => (x -> x > 0 ? x : 0) => "Number of fruits", color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_female_1) * mapping(:timestep, :carbon_allocation, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! Males (inflorescences)
df_male = vcat([s["Male"] for s in simulations]...)
df_male = leftjoin(df_male, meteo, on=[:Site, :timestep])
sort!(df_male, [:Site, :timestep])

df_male_month = combine(
    groupby(df_male, [:Site, :months_after_planting]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :state => (x -> sum(x .== "Harvested")) => :n_males_harvested,
    :state => (x -> sum(x .== "Scenescent")) => :n_males_Senescent,
    [:biomass, :state] => ((x, y) -> mean(x[findall(z -> z == "Scenescent", y)])) => :biomass_avg,
)

df_male_month.biomass_avg[isnan.(df_male_month.biomass_avg)] .= 0.0

data(df_male) * mapping(:months_after_planting, :carbon_demand, color=:Site => nonnumeric, marker=:node => nonnumeric) * visual(Scatter) |> draw()
data(df_male) * mapping(:months_after_planting, :carbon_allocation, color=:Site => nonnumeric, marker=:node => nonnumeric) * visual(Scatter) |> draw()

#! Average male inflorescence biomass:
data(df_male_month) * mapping(:months_after_planting, :biomass_avg => (x -> (x * 1e-3 / CC_Fruit) * dry_to_fresh_ratio) => "Average male inflorescence biomass (kg fresh mass)", color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_male_month) * mapping(:months_after_planting, :biomass_avg => (x -> x * 1e-3) => "Average male inflorescence biomass (kgC)", color=:Site => nonnumeric) * visual(Scatter) |> draw()

print(unique(df_male.node))
df_male_one = filter(row -> row[:node] == 1024 && row.Site == "PR", df_male)
data(df_male_one) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_male_one) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_male_one) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Scatter) |> draw()

carbon_demand_male = (1000 * (cumsum(df_male_one.TEff) / (10530 + 1800))) * 1.44
data(df_male_one) * mapping(:months_after_planting, :biomass, color=:Site => nonnumeric) * visual(Scatter) |> draw()
scatter(carbon_demand_male)

#! Leaf scale
df_leaf = vcat([s["Leaf"] for s in simulations]...)
df_leaf = leftjoin(df_leaf, meteo, on=[:Site, :timestep])
sort!(df_leaf, [:Site, :timestep])

#! control that all leaves have leaf area > 0
@test minimum(df_leaf.leaf_area) >= 0
@test minimum(df_leaf.carbon_demand) >= 0

#! control that the number of leaves at rank > 1 increases each step
df_leaves_rank_sup_1 = combine(groupby(df_leaf, [:Site, :timestep]), :rank => (r -> length(filter(x -> x > 0, r))) => :rank)
data(df_leaves_rank_sup_1) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! control that the number of leaves Opened is steady at mature stage, and is == to rank_leaf_pruning parameter
df_leaves_opened = combine(
    groupby(df_leaf, [:Site, :timestep]),
    :date => unique => :date,
    :months_after_planting => last => :months_after_planting,
    :state => (s -> length(filter(x -> x == "Opened", s))) => :leaves_opened,
    :state => (s -> length(filter(x -> x == "Pruned", s))) => :leaves_pruned,
    :state => (s -> length(filter(x -> x == "undetermined", s))) => :leaves_undetermined,
    :state => (s -> length(filter(x -> x == "Opened" || x == "Pruned", s))) => :leaves_emitted,
    :state => (s -> length(s)) => :leaves_all,
    :pruning_decision => (d -> length(filter(x -> x == "Pruned at rank", d))) => :pruned_at_rank,
    :pruning_decision => (d -> length(filter(x -> x == "Pruned at bunch harvest", d))) => :pruned_at_Harvest,
    :state => (s -> length(s)) => :n_leaves,
    [:state, :leaf_area] => ((s, a) -> sum(a[findall(x -> x == "Opened", s)])) => :leaf_area,
    :biomass => sum => :biomass,
)

CC_leaves = 0.45  # Carbon content of the leaves (gC g-1 dry mass)
df_leaves_year = combine(
    groupby(transform(df_leaves_opened, :date => ByRow(year) => :year), [:Site, :year]),
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass => (x -> minimum(x) * 1e-6 / CC_leaves / params_default["plot"]["scene_area"] * 10000) => :biomass_ton_ms,
)

data(df_leaves_opened) * mapping(:months_after_planting, :leaves_emitted, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_leaves_opened) * mapping(:months_after_planting, :leaf_area, color=:Site => nonnumeric) * visual(Lines) |> draw()


p_phytomers = data(dfs_plant) * mapping(:timestep, :phytomer_count, color=:Site => nonnumeric) * visual(Lines)
p_leaves_all = data(df_leaves_opened) * mapping(:timestep, :leaves_all, color=:Site => nonnumeric) * visual(Lines)
p_leaves_opened = data(df_leaves_opened) * mapping(:timestep, :leaves_opened, color=:Site => nonnumeric) * visual(Lines)
p_leaves_pruned = data(df_leaves_opened) * mapping(:timestep, :leaves_pruned, color=:Site => nonnumeric) * visual(Lines)
p_leaves_undeter = data(df_leaves_opened) * mapping(:timestep, :leaves_undetermined, color=:Site => nonnumeric) * visual(Lines)
# draw(p_phytomers + p_leaves_all)
draw(p_phytomers + p_leaves_opened + p_leaves_pruned + p_leaves_undeter)

#! Number of leaves undetermined (before opening) should be around 60:
@test maximum(df_leaves_opened.leaves_undetermined) == 60

#! Number of leaves opened + pruned + undetermined should be equal to the number of phytomers emitted:
phytomer_count_per_site = combine(groupby(dfs_plant, :Site), :phytomer_count => last => :phytomer_count)
leaves_emitted_per_site = combine(groupby(df_leaves_opened, :Site), [:leaves_emitted, :leaves_undetermined] => ((x, y) -> last(x) + last(y)) => :phytomer_count)
@test phytomer_count_per_site == leaves_emitted_per_site

#! Number of leaves opened + pruned should be around 100 between 50 and 100MAP:
data(df_leaves_opened) * mapping(:months_after_planting, :leaves_emitted, color=:Site => nonnumeric) * visual(Scatter) |> draw()
leaves_emitted_at_100MAP = filter(row -> row.months_after_planting == 100, df_leaves_opened).leaves_emitted |> mean
leaves_emitted_at_50MAP = filter(row -> row.months_after_planting == 49, df_leaves_opened).leaves_emitted |> mean
# Leaves emmitted is a cumulative value, so we compare with 50 to 100MAP instead:
leaves_emitted_50_to_100MAP = leaves_emitted_at_100MAP - leaves_emitted_at_50MAP # Should be around 100, with ~2 leaves per months emitted

@test leaves_emitted_50_to_100MAP > minimum(nb_leaves_50_to_100MAP_obs) && leaves_emitted_50_to_100MAP < maximum(nb_leaves_50_to_100MAP_obs) # mean ~ 109


data(df_leaves_opened) * mapping(:timestep, :leaves_opened, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_pruned, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :leaves_undetermined, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :pruned_at_rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaves_opened) * mapping(:timestep, :pruned_at_Harvest, color=:Site => nonnumeric) * visual(Scatter) |> draw()

#! Control that all leaves that are undetermined are also of rank <1
df_leaves_undetermined = filter(row -> row.state == "undetermined", df_leaf)
@test all(df_leaves_undetermined.rank .< 1)
df_leaves_pruned = filter(row -> row.state == "Pruned", df_leaf)
# @test all(df_leaves_pruned.rank .> params_default["management"]["rank_leaf_pruning"] .|| df_leaves_pruned.TT_since_init .> params_default["phenology"]["female"]["TT_harvest"])

#! controlling leaves biomass (we expect 20 t dry mass ha-1 at 13 years old, see Dufrene et al. 1990 Oléagineux):
data(df_leaves_year) * mapping(:year, :biomass_ton_ms => "Leaf biomass (t[ms] ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

unique(df_leaves_pruned.node) |> print
df_leaves_pruned_one = filter(x -> x.node == 278 && x.Site == "SMSE", df_leaves_pruned)
minimum(df_leaves_pruned_one.rank) # Pruned at rank 30, very early
df_leaf_278 = filter(x -> x.node == 278 && x.Site == "SMSE", df_leaf)
df_leaf_278.rank[df_leaf_278.rank.<0] .= 0
scatter(df_leaf_278.timestep, df_leaf_278.rank, color=:green, markersize=3)
data(df_leaf_278) * mapping(:timestep, :rank, color=:state) * visual(Scatter) |> draw()
data(df_leaf_278) * mapping(:timestep, :pruning_decision, color=:state) * visual(Scatter) |> draw()
data(df_leaf_278) * mapping(:timestep, :TT_since_init, color=:state) * visual(Scatter) |> draw()
df_leaf_278.final_potential_area

filter(x -> x.state == "Pruned", df_leaf_278).TT_since_init |> minimum
filter(x -> x.state == "undetermined", df_leaf_278).TT_since_init |> maximum


data(df_leaf_278) * mapping(:timestep, :state, color=:state) * visual(Scatter) |> draw()
scatter(df_leaf_278.timestep, df_leaf_278.leaf_area, color=:green, markersize=3)

df_leaf_one = filter(row -> row.Site == "PR" && row.node == 679, df_leaf)

data(df_leaf_one) * mapping(:timestep, :state, color=:state) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :carbon_demand, color=:state) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :biomass, color=:state) * visual(Scatter) |> draw()

df_leaf_TOWE = filter(row -> row.Site == "SMSE", df_leaf)
df_leaf_TOWE_ts_end = filter(row -> row.timestep == 4160, df_leaf_TOWE)
df_leaf_TOWE_ts_end_opened = filter(x -> x.state == "Opened", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_undetermined = filter(x -> x.state == "undetermined", df_leaf_TOWE_ts_end)
df_leaf_TOWE_ts_end_pruned = filter(x -> x.state == "Pruned", df_leaf_TOWE_ts_end)

data(df_leaf_TOWE) * mapping(:timestep, :final_potential_area => (x -> x * 560.0)) * visual(Scatter) |> draw()

unique(df_leaf.node) |> print
df_leaf_one = filter(row -> row[:node] == 80, df_leaf)
data(df_leaf_one) * mapping(:timestep, :leaf_area, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :state, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_leaf_one) * mapping(:timestep, :pruning_decision, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(filter(row -> row.timestep > 500, df_leaf_one)) * mapping(:timestep, :rank, color=:Site => nonnumeric) * visual(Scatter) |> draw()

data(df_leaf_TOWE) * mapping(:timestep, :pruning_decision, color=:Site => nonnumeric) * visual(Scatter) |> draw()


#! Phytomer scale
df_phytomer = vcat([s["Phytomer"] for s in simulations]...)
df_phytomer = leftjoin(df_phytomer, meteo, on=[:Site, :timestep])
sort!(df_phytomer, [:Site, :timestep])

scatter(df_phytomer.timestep, df_phytomer.TEff, color=:green, markersize=3)
data(df_phytomer) * mapping(:timestep, :TEff, color=:Site => nonnumeric) * visual(Scatter) |> draw()
data(df_phytomer) * mapping(:timestep, :TT_since_init, color=:Site => nonnumeric) * visual(Scatter) |> draw()

df_phytomer_SMSE = filter(x -> x.Site == "SMSE", df_phytomer)
data(df_phytomer_SMSE) * mapping(:timestep, :TT_since_init, color=:node) * visual(Scatter) |> draw()

filter(row -> row.node == 6, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

filter(row -> row.node == 6, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

filter(row -> row.node == 387, df_phytomer_SMSE) |>
(x -> data(x) * mapping(:timestep, :state, color=:node => nonnumeric) * visual(Lines)) |>
draw()

#! Internodes:
df_internode = vcat([s["Internode"] for s in simulations]...)
df_internode = leftjoin(df_internode, meteo, on=[:Site, :timestep])
sort!(df_internode, [:Site, :timestep])

# plant scale results for internodes:
df_internodes_plant = combine(
    groupby(df_internode, [:Site, :timestep]),
    :date => unique => :date,
    :months_after_planting => last => :months_after_planting,
    :biomass => sum => :biomass,
    :height => sum => :height,
    :radius => maximum => :radius,
)

CC_internode = 0.45  # Carbon content of the internodes (gC g-1 dry mass)
df_internodes_year = combine(
    groupby(transform(df_internodes_plant, :date => ByRow(year) => :year), [:Site, :year]),
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass => (x -> minimum(x) * 1e-6 / CC_internode / params_default["plot"]["scene_area"] * 10000) => :biomass_ton_ms,
    :height => minimum => :height,
    :radius => (x -> minimum(x) * 2) => :diameter,
)

#! controlling internodes biomass (we expect 14.68 t dry mass ha-1 at 13 years old, see Dufrene et al. 1990 Oléagineux):
data(df_internodes_year) * mapping(:year, :biomass_ton_ms => "Internodes biomass (t[ms] ha⁻¹ year⁻¹)", color=:Site => nonnumeric) * visual(Lines) |> draw()

#! controlling stem height:
data(df_internodes_year) * mapping(:year, :height => "Stem height (m)", color=:Site => nonnumeric) * visual(Lines) |> draw()

#! controlling stem diameter:
data(df_internodes_year) * mapping(:year, :diameter => "Stem diameter (m)", color=:Site => nonnumeric) * visual(Lines) |> draw()

df_internode_7 = filter(row -> row[:node] == 7 && row.Site == "PR", df_internode)
df_internode_one = filter(row -> row[:node] == 853 && row.Site == "PR", df_internode)

data(df_internode_7) * mapping(:timestep, :potential_height, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :carbon_demand, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :Rm, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :biomass, color=:Site => nonnumeric) * visual(Lines) |> draw()
data(df_internode_7) * mapping(:timestep, :initiation_age, color=:Site => nonnumeric) * visual(Lines) |> draw()

reserves_trunk = combine(groupby(df_internode, :timestep), :reserve => sum) ./ 1000
lines(reserves_trunk.reserve_sum)

#! Using the notebook instead:
using Pluto, XPalm
XPalm.notebook("xpalm_notebook.jl")
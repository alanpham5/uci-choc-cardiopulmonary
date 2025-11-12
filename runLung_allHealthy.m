%% Healthy Patient Simulation Script (Updated with LC deviation and Alveolar Flow)
clearvars; close all; rng('shuffle');

%% User parameters
numPatients = 62;
outputFilename = 'healthy_patient_lung_sim_results.csv';

%% Constants / Reference values
HIref = 2.5;
Cs = 0.005;
FR = 15; PEEP = 5; PP = 10; E = 2;

% Default mechanical parameters (fixed)
LC_ref = 0.2;   % Reference Lung compliance (L/cmH2O)
TC_ref = 0.2;   % Thoracic compliance (L/cmH2O)
CR_ref = 2.0;   % Central airway resistance (cmH2O·s/L)
PR_ref = 0.5;   % Peripheral airway resistance (cmH2O·s/L)

%% Generate demographic data
Age = randi([13,21], numPatients, 1);
Gender = strings(numPatients,1);
Ht_cm = zeros(numPatients,1);
Wt_kg = zeros(numPatients,1);
FEV1 = zeros(numPatients,1);
FEF2575 = zeros(numPatients,1);

for i = 1:numPatients
    if rand() < 0.5
        Gender(i) = "Male";
        adult_mean_h = 175; adult_sd_h = 7; min_h = 150; max_h = 200;
    else
        Gender(i) = "Female";
        adult_mean_h = 162; adult_sd_h = 7; min_h = 145; max_h = 185;
    end

    frac = 0.75 + 0.20 * ((Age(i)-13)/8);
    Ht_mean = frac * adult_mean_h;
    Ht_candidate = round(Ht_mean + adult_sd_h * randn(), 1);
    while Ht_candidate < min_h || Ht_candidate > max_h
        Ht_candidate = round(Ht_mean + adult_sd_h * randn(), 1);
    end
    Ht_cm(i) = Ht_candidate;

    BMI = 18.5 + (25-18.5)*rand();
    H_m = Ht_cm(i)/100;
    Wt_kg(i) = round(BMI * H_m^2, 1);

    meanFEV1 = 0.025*Ht_cm(i) - 1.0;
    FEV1(i) = round(max(0.5, meanFEV1 + 0.3*randn()), 2);
    FEF2575(i) = round(1.5 + 1.5*rand(), 2);
end

%% Initialize results table
results = table();

%% Load Simulink model
modelName = 'Modelo_Respiratorio';
load_system(modelName);

%% Iterate through patients
for patientIndex = 1:numPatients
    fprintf('Processing healthy patient %d/%d...\n', patientIndex, numPatients);

    age = Age(patientIndex);
    gender = Gender(patientIndex);
    weight = Wt_kg(patientIndex);
    height = Ht_cm(patientIndex);
    HI = HIref;
    FEV1v = FEV1(patientIndex);
    FEF2575v = FEF2575(patientIndex);

    % Mechanical parameters with variability
    variability = 0.15; % percentage variation
    LC = LC_ref * (1 + variability*randn()); 
    TC = TC_ref * (1 + variability*randn());
    CR = CR_ref * (1 + variability*randn());
    PR = PR_ref * (1 + variability*randn());

    % Clamp values within physiological limits
    LC = max(min(LC, 0.3), 0.05);  
    TC = max(min(TC, 1.0), 0.05);
    CR = max(min(CR, 5.0), 0.5);
    PR = max(min(PR, 1.0), 0.05);

    % Assign to Simulink (GUI-style included)
    assignin('base','CL', LC); assignin('base','Cw', TC);
    assignin('base','Rc', CR); assignin('base','Rp', PR);
    assignin('base','Cs', Cs);
    assignin('base','f', LC); assignin('base','g', TC);
    assignin('base','h', CR); assignin('base','j', PR); assignin('base','k', Cs);
    assignin('base','FR', FR); assignin('base','PEEP', PEEP);
    assignin('base','PP', PP); assignin('base','E', E);
    assignin('base','a', FR); assignin('base','b', PEEP);
    assignin('base','c', PP); assignin('base','d', round(1/(1+1),2)*100);

    % Run Simulink simulation
    try
        simOut = sim(modelName, 'StopTime', '10');

        BioData = simOut.get('BioData');
        volumen = simOut.get('volumen');
        time = BioData.time;

        % Steady-state indices
        ss_idx = time >= 2;
        lung_ss = volumen(ss_idx,2);
        transp_ss = BioData.signals(3).values(ss_idx);
        alv_ss = BioData.signals(2).values(ss_idx);
        flow_ss = BioData.signals(4).values(ss_idx);
        dead_ss = BioData.signals(5).values(ss_idx);
        alvFlow_ss = BioData.signals(6).values(ss_idx); % Alveolar flow

        % Store metrics
        patientResult = table();
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1v;
        patientResult.FEF2575 = FEF2575v;

        patientResult.LC = round(LC,4);
        patientResult.TC = round(TC,4);
        patientResult.CR = round(CR,4);
        patientResult.PR = round(PR,4);
        patientResult.Cs = round(Cs,4);

        patientResult.Sim_LungVol_Mean = round(mean(lung_ss),4);
        patientResult.Sim_LungVol_Max = round(max(lung_ss),4);
        patientResult.Sim_LungVol_Std = round(std(lung_ss),4);
        patientResult.Sim_TransP_Mean = round(mean(transp_ss),4);
        patientResult.Sim_TransP_Max = round(max(transp_ss),4);
        patientResult.Sim_TransP_Std = round(std(transp_ss),4);
        patientResult.Sim_AlvP_PeakMax = round(max(alv_ss),4);
        patientResult.Sim_AlvP_PeakMin = round(min(alv_ss),4);
        patientResult.Sim_Flow_PeakMax = round(max(flow_ss),4);
        patientResult.Sim_Flow_Std = round(std(flow_ss),4);
        patientResult.Sim_DeadFlow_PeakMax = round(max(dead_ss),4);
        patientResult.Sim_DeadFlow_Std = round(std(dead_ss),4);
        % Alveolar flow metrics
        patientResult.Sim_AlvFlow_Max = round(max(alvFlow_ss),4);
        patientResult.Sim_AlvFlow_Mean = round(mean(alvFlow_ss),4);
        patientResult.Sim_AlvFlow_Std = round(std(alvFlow_ss),4);

        results = [results; patientResult];

    catch ME
        fprintf('  ERROR simulating patient %d: %s\n', patientIndex, ME.message);
        patientResult = table();
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1v;
        patientResult.FEF2575 = FEF2575v;
        patientResult.LC = NaN; patientResult.TC = NaN;
        patientResult.CR = NaN; patientResult.PR = NaN;
        patientResult.Cs = round(Cs,4);
        patientResult.Sim_LungVol_Mean = NaN; patientResult.Sim_LungVol_Max = NaN; patientResult.Sim_LungVol_Std = NaN;
        patientResult.Sim_TransP_Mean = NaN; patientResult.Sim_TransP_Max = NaN; patientResult.Sim_TransP_Std = NaN;
        patientResult.Sim_AlvP_PeakMax = NaN; patientResult.Sim_AlvP_PeakMin = NaN;
        patientResult.Sim_Flow_PeakMax = NaN; patientResult.Sim_Flow_Std = NaN;
        patientResult.Sim_DeadFlow_PeakMax = NaN; patientResult.Sim_DeadFlow_Std = NaN;
        patientResult.Sim_AlvFlow_Max = NaN; patientResult.Sim_AlvFlow_Mean = NaN; patientResult.Sim_AlvFlow_Std = NaN;

        results = [results; patientResult];
    end
end

%% Save results
writetable(results, outputFilename);
fprintf('\nHealthy patient batch processing complete!\n');
fprintf('Results saved to: %s\n', outputFilename);

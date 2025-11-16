%% User parameters
infile = 'choc-data-all.csv';
outputFilename = 'patient_lung_sim_results.csv';

%% Load patient data
T = readtable(infile, 'PreserveVariableNames', true);
numPatients = size(T, 1);
results = table();

%% Constants
HIref = 2.5;         
Cs = 0.005;         

% Sigmoid coefficients for parameter scaling
c_FVC = 1.00; w_FVC = 0.10;  % Lung compliance (% predicted)
c_TC  = 10.0; w_TC  = 3.2;   % Thoracic compliance
c_CR  = 1.00; w_CR  = 0.10;  % Central resistance (% predicted)
c_PR  = 1.00; w_PR  = 0.10;  % Peripheral resistance (% predicted)

% Maximum fractional adjustments
L_LC = 0.20;     % Max fractional drop for LC
L_TC = 0.8;      % Max fractional drop for TC
L_CR = 0.20;     % Max 20% increase for CR
L_PR = 0.40;     % Max 40% increase for PR

% Additional shape parameter for LC
gamma_LC = 1.5; % Steepness control for LC

% Baseline resistances (fixed)
CRo = 2.0;      % Central airway resistance
PRo = 0.5;      % Peripheral airway resistance

% Ventilator settings
FR = 15;  % Breathing frequency
PEEP = 5; % Positive End-Expiratory Pressure
PP = 10;  % Peak Pressure
E = 2;    % Inhale:Exhale ratio

%% Iterate through all patients
for patientIndex = 1:numPatients
    fprintf('Processing patient %d/%d...\n', patientIndex, numPatients);
    
    try
        %% Extract patient data
        age = T.Age(patientIndex);
        gender = string(T.Gender(patientIndex));
        weight = T.("Wt (kg)")(patientIndex);
        height = T.("Ht (cm)")(patientIndex);
        HI = T.("Mean HI")(patientIndex);
        FEV1 = T.FEV1(patientIndex);
        FEF2575 = T.("FEF 25-75")(patientIndex);
        FVCpct = T.("FVC% predicted")(patientIndex);
        PEFpct = T.("PEF %predicted")(patientIndex);
        FEF2575pct_post = T.("FEF25-75 post %predicted")(patientIndex);

        %% Compute patient-specific parameters
        % Age-based thoracic compliance
        if age >=6 && age <=10
            TCo = 2;
        elseif age >10 && age <=17
            TCo = 1.75;
        else
            TCo = 1.25;
        end

        % Height-based baseline lung compliance
        LCo = (0.713 * height.^2.836 * 1e-4) / 1000;

        % --- Lung Compliance (FVC % predicted, decreasing relation) ---
        S_FVC = 1 / (1 + exp(-(FVCpct - c_FVC)/w_FVC));
        S_ref_FVC = 1 / (1 + exp(-(1.0 - c_FVC)/w_FVC)); % reference at 100%
        norm_FVC = max(0, (S_ref_FVC - S_FVC) / S_ref_FVC);
        LC = LCo * (1 - L_LC * (norm_FVC ^ gamma_LC));  % decreases with FVCpct

        % --- Thoracic Compliance (HI-based) ---
        S_HI_TC  = 1 / (1 + exp(-(HI - c_TC)/w_TC));
        S_ref_TC = 1 / (1 + exp(-(HIref - c_TC)/w_TC));
        norm_TC  = max(0, (S_HI_TC - S_ref_TC) / (1 - S_ref_TC));
        TC = TCo * (1 - L_TC * norm_TC);

        % --- Central Airway Resistance (PEF % predicted, flipped) ---
        S_PEF = 1 / (1 + exp(-(PEFpct - c_CR)/w_CR));
        S_ref_PEF = 1 / (1 + exp(-(1.0 - c_CR)/w_CR));  % reference 100%
        norm_PEF = max(0, 1 - (S_PEF / S_ref_PEF));
        CR = CRo * (1 + L_CR * norm_PEF);

        % --- Peripheral Airway Resistance (FEF25-75 % predicted, flipped) ---
        S_FEF = 1 / (1 + exp(-(FEF2575pct_post - c_PR)/w_PR));
        S_ref_FEF = 1 / (1 + exp(-(1.0 - c_PR)/w_PR));
        norm_FEF = max(0, 1 - (S_FEF / S_ref_FEF));
        PR = PRo * (1 + L_PR * norm_FEF);

        %% Assign parameters to base workspace for Simulink
        assignin('base','CL', LC);
        assignin('base','Cw', TC);
        assignin('base','Rc', CR);
        assignin('base','Rp', PR);
        assignin('base','Cs', Cs);

        % GUI-style variable names
        assignin('base','f', LC);
        assignin('base','g', TC);
        assignin('base','h', CR);
        assignin('base','j', PR);
        assignin('base','k', Cs);

        % Ventilator parameters
        assignin('base','FR', FR);
        assignin('base','PEEP', PEEP);
        assignin('base','PP', PP);
        assignin('base','E', E);

        %% Run Simulink simulation
        modelName = 'Modelo_Respiratorio';
        load_system(modelName);
        simOut = sim(modelName, 'StopTime', '10');

        %% Extract signals
        BioData = simOut.get('BioData');
        volumen = simOut.get('volumen');
        time = BioData.time;

        dt = time(2) - time(1); % Time step
        samples_per_second = round(1 / dt);
        start_index = samples_per_second + 1;
        steady_idx = start_index:length(time);

        ventilator_pressure = BioData.signals(1).values(steady_idx);
        alveolar_pressure = BioData.signals(2).values(steady_idx);
        transpulmonary_pressure = BioData.signals(3).values(steady_idx);
        respiratory_flow = BioData.signals(4).values(steady_idx);
        dead_space_flow = BioData.signals(5).values(steady_idx);
        alveolar_flow = BioData.signals(6).values(steady_idx);
        lung_volume = volumen(steady_idx,2);

        %% Compute metrics
        Sim_Lung_Volume_Mean = mean(lung_volume);
        Sim_Lung_Volume_Max = max(lung_volume);
        Sim_Lung_Volume_Std_Dev = std(lung_volume);

        Sim_Transpulmonary_Pressure_Mean = mean(transpulmonary_pressure);
        Sim_Transpulmonary_Pressure_Max = max(transpulmonary_pressure);
        Sim_Transpulmonary_Pressure_Std_Dev = std(transpulmonary_pressure);

        Sim_Alv_Pressure_Peak_Max = max(alveolar_pressure);
        Sim_Alv_Pressure_Peak_Min = min(alveolar_pressure);

        Sim_Respiratory_Flow_Peak_Max = max(respiratory_flow);
        Sim_Respiratory_Flow_Std_Dev = std(respiratory_flow);

        Sim_Dead_Space_Flow_Peak_Max = max(dead_space_flow);
        Sim_Dead_Space_Flow_Std_Dev = std(dead_space_flow);
        
        Sim_Alveolar_Flow_Max = max(alveolar_flow);
        Sim_Alveolar_Flow_Mean = mean(alveolar_flow);
        Sim_Alveolar_Flow_Std_Dev = std(alveolar_flow);
        
        %% Store results
        patientResult = table();
        
        % Patient demographics
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1;
        patientResult.FEF2575 = FEF2575;
        patientResult.FVCpct = FVCpct;
        patientResult.PEFpct = PEFpct;
        patientResult.FEF2575pct_post = FEF2575pct_post;
        
        % Mechanical parameters
        patientResult.LC = round(LC,4);
        patientResult.TC = round(TC,4);
        patientResult.CR = round(CR,4);
        patientResult.PR = round(PR,4);
        patientResult.Cs = round(Cs,4);
        
        % Simulation metrics
        patientResult.Sim_LungVol_Mean = round(Sim_Lung_Volume_Mean,4);
        patientResult.Sim_LungVol_Max = round(Sim_Lung_Volume_Max,4);
        patientResult.Sim_LungVol_Std = round(Sim_Lung_Volume_Std_Dev,4);
        
        patientResult.Sim_TransP_Mean = round(Sim_Transpulmonary_Pressure_Mean,4);
        patientResult.Sim_TransP_Max = round(Sim_Transpulmonary_Pressure_Max,4);
        patientResult.Sim_TransP_Std = round(Sim_Transpulmonary_Pressure_Std_Dev,4);
        
        patientResult.Sim_AlvP_PeakMax = round(Sim_Alv_Pressure_Peak_Max,4);
        patientResult.Sim_AlvP_PeakMin = round(Sim_Alv_Pressure_Peak_Min,4);
        
        patientResult.Sim_Flow_PeakMax = round(Sim_Respiratory_Flow_Peak_Max,4);
        patientResult.Sim_Flow_Std = round(Sim_Respiratory_Flow_Std_Dev,4);
        
        patientResult.Sim_DeadFlow_PeakMax = round(Sim_Dead_Space_Flow_Peak_Max,4);
        patientResult.Sim_DeadFlow_Std = round(Sim_Dead_Space_Flow_Std_Dev,4);
        
        patientResult.Sim_AlvFlow_Max = round(Sim_Alveolar_Flow_Max,4);
        patientResult.Sim_AlvFlow_Mean = round(Sim_Alveolar_Flow_Mean,4);
        patientResult.Sim_AlvFlow_Std = round(Sim_Alveolar_Flow_Std_Dev,4);

        results = [results; patientResult];

        fprintf('  Patient %d completed successfully.\n', patientIndex);
        fprintf('  Samples used: %d (after 1s), dt=%.4f\n', length(steady_idx), dt);
        fprintf('  LC=%.4f, TC=%.4f, LungVol=%.4f\n', LC, TC, Sim_Lung_Volume_Mean);

    catch ME
        fprintf('  ERROR processing patient %d: %s\n', patientIndex, ME.message);
        
        patientResult = table();
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1;
        patientResult.FEF2575 = FEF2575;
        patientResult.FVCpct = FVCpct;
        patientResult.PEFpct = PEFpct;
        patientResult.FEF2575pct_post = FEF2575pct_post;
        
        patientResult.LC = NaN;
        patientResult.TC = NaN;
        patientResult.CR = NaN;
        patientResult.PR = NaN;
        patientResult.Cs = round(Cs,4);
        
        patientResult.Sim_LungVol_Mean = NaN;
        patientResult.Sim_LungVol_Max = NaN;
        patientResult.Sim_LungVol_Std = NaN;
        
        patientResult.Sim_TransP_Mean = NaN;
        patientResult.Sim_TransP_Max = NaN;
        patientResult.Sim_TransP_Std = NaN;
        
        patientResult.Sim_AlvP_PeakMax = NaN;
        patientResult.Sim_AlvP_PeakMin = NaN;
        
        patientResult.Sim_Flow_PeakMax = NaN;
        patientResult.Sim_Flow_Std = NaN;
        
        patientResult.Sim_DeadFlow_PeakMax = NaN;
        patientResult.Sim_DeadFlow_Std = NaN;
        
        patientResult.Sim_AlvFlow_Max = NaN;
        patientResult.Sim_AlvFlow_Mean = NaN;
        patientResult.Sim_AlvFlow_Std = NaN;

        results = [results; patientResult];
    end
end

%% Save results to CSV
writetable(results, outputFilename);

% Display summary statistics
successfulPatients = sum(~isnan(results.Sim_LungVol_Mean));
fprintf('\nBatch processing complete!\n');
fprintf('Results saved to: %s\n', outputFilename);
fprintf('Successful simulations: %d/%d (%.1f%%)\n', ...
    successfulPatients, numPatients, successfulPatients/numPatients*100);

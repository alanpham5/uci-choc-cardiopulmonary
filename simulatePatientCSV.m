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
c_LC = 9.5;  w_LC = 3.0;   % Lung compliance
c_TC = 10.0; w_TC = 3.2;   % Thoracic compliance
c_CR = 1.00; w_CR = 0.10;  % Central resistance (% predicted)
c_PR = 1.00; w_PR = 0.10;  % Peripheral resistance (% predicted)

% Maximum fractional adjustments
L_LC = 0.8;     % Max fractional drop for LC
L_TC = 0.8;     % Max fractional drop for TC
L_CR = 0.20;    % Max 20% increase for CR
L_PR = 0.40;    % Max 40% increase for PR

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

        % Height-based lung compliance
        LCo = (0.713 * height.^2.836 * 1e-4) / 1000;

        % --- Lung Compliance (HI-based) ---
        S_HI_LC  = 1 / (1 + exp(-(HI - c_LC)/w_LC));
        S_ref_LC = 1 / (1 + exp(-(HIref - c_LC)/w_LC));
        norm_LC  = max(0, (S_HI_LC - S_ref_LC) / (1 - S_ref_LC));
        LC = LCo * (1 - L_LC * norm_LC);

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

        % Use only steady-state (time > 2s)
        steady_idx = time >= 2;
        transpulmonary_pressure_ss = BioData.signals(3).values(steady_idx);
        respiratory_flow_ss = BioData.signals(4).values(steady_idx);
        dead_space_flow_ss = BioData.signals(5).values(steady_idx);
        lung_volume_ss = volumen(steady_idx,2);
        alveolar_pressure_ss = BioData.signals(2).values(steady_idx);

        %% Compute metrics
        Sim_Lung_Volume_Mean = mean(lung_volume_ss);
        Sim_Lung_Volume_Max = max(lung_volume_ss);
        Sim_Lung_Volume_Std_Dev = std(lung_volume_ss);

        Sim_Transpulmonary_Pressure_Mean = mean(transpulmonary_pressure_ss);
        Sim_Transpulmonary_Pressure_Max = max(transpulmonary_pressure_ss);
        Sim_Transpulmonary_Pressure_Std_Dev = std(transpulmonary_pressure_ss);

        Sim_Alv_Pressure_Peak_Max = max(alveolar_pressure_ss);
        Sim_Alv_Pressure_Peak_Min = min(alveolar_pressure_ss);

        Sim_Respiratory_Flow_Peak_Max = max(respiratory_flow_ss);
        Sim_Respiratory_Flow_Std_Dev = std(respiratory_flow_ss);

        Sim_Dead_Space_Flow_Peak_Max = max(dead_space_flow_ss);
        Sim_Dead_Space_Flow_Std_Dev = std(dead_space_flow_ss);

        %% Store results
        patientResult = table(patientIndex, age, gender, weight, height, HI, FEV1, FEF2575,...
            round(LC,4), round(TC,4), round(CR,4), round(PR,4), round(Cs,4),...
            round(Sim_Lung_Volume_Mean,4), round(Sim_Lung_Volume_Max,4), round(Sim_Lung_Volume_Std_Dev,4),...
            round(Sim_Transpulmonary_Pressure_Mean,4), round(Sim_Transpulmonary_Pressure_Max,4), round(Sim_Transpulmonary_Pressure_Std_Dev,4),...
            round(Sim_Alv_Pressure_Peak_Max,4), round(Sim_Alv_Pressure_Peak_Min,4),...
            round(Sim_Respiratory_Flow_Peak_Max,4), round(Sim_Respiratory_Flow_Std_Dev,4),...
            round(Sim_Dead_Space_Flow_Peak_Max,4), round(Sim_Dead_Space_Flow_Std_Dev,4),...
            'VariableNames', {'patientIndex','age','gender','weight','height','HI','FEV1','FEF2575',...
            'LC','TC','CR','PR','Cs','Sim_LungVol_Mean','Sim_LungVol_Max','Sim_LungVol_Std',...
            'Sim_TransP_Mean','Sim_TransP_Max','Sim_TransP_Std','Sim_AlvP_PeakMax','Sim_AlvP_PeakMin',...
            'Sim_Flow_PeakMax','Sim_Flow_Std','Sim_DeadFlow_PeakMax','Sim_DeadFlow_Std'});

        results = [results; patientResult];

        fprintf('  Patient %d completed successfully.\n', patientIndex);

    catch ME
        fprintf('  ERROR processing patient %d: %s\n', patientIndex, ME.message);
        % In case of error, store NaNs for metrics
        patientResult = table(patientIndex, age, gender, weight, height, HI, FEV1, FEF2575,...
            NaN, NaN, NaN, NaN, Cs,...
            NaN, NaN, NaN,...
            NaN, NaN, NaN,...
            NaN, NaN,...
            NaN, NaN, NaN, NaN,...
            'VariableNames', {'patientIndex','age','gender','weight','height','HI','FEV1','FEF2575',...
            'LC','TC','CR','PR','Cs','Sim_LungVol_Mean','Sim_LungVol_Max','Sim_LungVol_Std',...
            'Sim_TransP_Mean','Sim_TransP_Max','Sim_TransP_Std','Sim_AlvP_PeakMax','Sim_AlvP_PeakMin',...
            'Sim_Flow_PeakMax','Sim_Flow_Std','Sim_DeadFlow_PeakMax','Sim_DeadFlow_Std'});
        results = [results; patientResult];
    end
end

%% Save results to CSV
writetable(results, outputFilename);
fprintf('\nBatch processing complete!\n');
fprintf('Results saved to: %s\n', outputFilename);
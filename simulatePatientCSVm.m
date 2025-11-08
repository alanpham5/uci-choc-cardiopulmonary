%% User parameters
infile = 'choc-data-all.csv';
outputFilename = 'patient_lung_sim_results.csv';

%% Load patient data
T = readtable(infile, 'PreserveVariableNames', true);
numPatients = 62;
results = table();

%% Constants
HIref = 2.5;
% Sigmoid coefficients for each parameter
c_LC = 9.5;  w_LC = 3.0;
c_TC = 10.0; w_TC = 3.2;
c_CR = 10.5; w_CR = 2.8;
c_PR = 9.0;  w_PR = 3.5;

Cs = 0.005; % Fixed series compliance

% Total drop fractions
L_LC = 0.8;
L_TC = 0.8;
L_CR = 0.8;
L_PR = 0.8;

% Ventilator Settings
FR = 15; % Breathing frequency
PEEP = 0; % Positive End-Expiratory Pressure
PP = 10; % Peak Pressure
E = 1; % Inhale:Exhale

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
        
        %% Compute patient-specific parameters
        % Age-based thoracic compliance
        if age>=6 && age<=10
            TCo=2;
        elseif age>10 && age<=17
            TCo=1.75;
        else
            TCo=1.25;
        end

        % Height-based lung compliance
        LCo = (0.713 * height.^2.836 * 1e-4) / 1000;

        % Baseline resistances
        if gender=="Female"
            CRo=1.156; PRo=0.204;
        else
            CRo=0.867; PRo=0.153;
        end

        % Sigmoid response for each parameter
        S_HI_LC  = 1/(1 + exp(-(HI - c_LC)/w_LC));
        S_ref_LC = 1/(1 + exp(-(HIref - c_LC)/w_LC));
        norm_LC  = (S_HI_LC - S_ref_LC) / (1 - S_ref_LC);

        S_HI_TC  = 1/(1 + exp(-(HI - c_TC)/w_TC));
        S_ref_TC = 1/(1 + exp(-(HIref - c_TC)/w_TC));
        norm_TC  = (S_HI_TC - S_ref_TC) / (1 - S_ref_TC);

        S_HI_CR  = 1/(1 + exp(-(HI - c_CR)/w_CR));
        S_ref_CR = 1/(1 + exp(-(HIref - c_CR)/w_CR));
        norm_CR  = (S_HI_CR - S_ref_CR) / (1 - S_ref_CR);

        S_HI_PR  = 1/(1 + exp(-(HI - c_PR)/w_PR));
        S_ref_PR = 1/(1 + exp(-(HIref - c_PR)/w_PR));
        norm_PR  = (S_HI_PR - S_ref_PR) / (1 - S_ref_PR);

        % Apply sigmoid-based decreases
        if HI <= HIref
            LC = LCo;
            TC = TCo;
            CR = CRo;
            PR = PRo;
        else
            LC = LCo * (1 - L_LC * norm_LC);
            TC = TCo * (1 - L_TC * norm_TC);
            CR = CRo * (1 - L_CR * norm_CR);
            PR = PRo * (1 - L_PR * norm_PR);
        end

        %% Assign parameters to base workspace for Simulink
        assignin('base','CL', LC);
        assignin('base','Cw', TC);
        assignin('base','Rc', CR);
        assignin('base','Rp', PR);
        assignin('base','Cs', Cs);

        % Also assign GUI-style variable names (full precision)
        assignin('base','f', LC);   % CL
        assignin('base','g', TC);   % Cw
        assignin('base','h', CR);   % Rc
        assignin('base','j', PR);   % Rp
        assignin('base','k', Cs);   % Cs

        % Ventilator parameters
        assignin('base','FR', FR);
        assignin('base','PEEP', PEEP);
        assignin('base','PP', PP);
        assignin('base','E', E);

        % GUI-style equivalents
        assignin('base','a', FR);   % FR
        assignin('base','b', PEEP);    % PEEP
        assignin('base','c', PP);   % PP
        assignin('base','d', round(1/(1+1),2)*100);

        %% Run Simulink simulation
        modelName = 'Modelo_Respiratorio';
        load_system(modelName);
        simOut = sim(modelName, 'StopTime', '10');

        %% Extract signals
        BioData = simOut.get('BioData');
        volumen = simOut.get('volumen');
        time = BioData.time;
        
        % Extract individual signals
        ventilator_pressure = BioData.signals(1).values;
        alveolar_pressure = BioData.signals(2).values;
        transpulmonary_pressure = BioData.signals(3).values;
        respiratory_flow = BioData.signals(4).values;
        dead_space_flow = BioData.signals(5).values;
        lung_volume = volumen(:,2);
        
        % Remove initial transient
        steady_state_idx = time >= 2;
        time_ss = time(steady_state_idx);
        transpulmonary_pressure_ss = transpulmonary_pressure(steady_state_idx);
        respiratory_flow_ss = respiratory_flow(steady_state_idx);
        dead_space_flow_ss = dead_space_flow(steady_state_idx);
        lung_volume_ss = lung_volume(steady_state_idx);
        alveolar_pressure_ss = alveolar_pressure(steady_state_idx);
        
        %% Calculate all requested metrics
        % Lung Volume metrics
        Sim_Lung_Volume_Mean = mean(lung_volume_ss);
        Sim_Lung_Volume_Max = max(lung_volume_ss);
        Sim_Lung_Volume_Std_Dev = std(lung_volume_ss);
        
        % Transpulmonary Pressure metrics
        Sim_Transpulmonary_Pressure_Mean = mean(transpulmonary_pressure_ss);
        Sim_Transpulmonary_Pressure_Max = max(transpulmonary_pressure_ss);
        Sim_Transpulmonary_Pressure_Std_Dev = std(transpulmonary_pressure_ss);
        
        % Alveolar Pressure metrics
        Sim_Alv_Pressure_Peak_Max = max(alveolar_pressure_ss);
        Sim_Alv_Pressure_Peak_Min = min(alveolar_pressure_ss);
        
        % Respiratory Flow metrics
        Sim_Respiratory_Flow_Peak_Max = max(respiratory_flow_ss);
        Sim_Respiratory_Flow_Std_Dev = std(respiratory_flow_ss);
        
        % Dead Space Flow metrics
        Sim_Dead_Space_Flow_Peak_Max = max(dead_space_flow_ss);
        Sim_Dead_Space_Flow_Std_Dev = std(dead_space_flow_ss);
        
        %% Store results for this patient
        patientResult = table();
        
        % Patient demographics and input data
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1;
        patientResult.FEF2575 = FEF2575;
        
        % Calculated mechanical parameters
        patientResult.LC = round(LC, 4);
        patientResult.TC = round(TC, 4);
        patientResult.CR = round(CR, 4);
        patientResult.PR = round(PR, 4);
        patientResult.Cs = round(Cs, 4);
        
        % Simulation metrics
        patientResult.Sim_LungVol_Mean = round(Sim_Lung_Volume_Mean, 4);
        patientResult.Sim_LungVol_Max = round(Sim_Lung_Volume_Max, 4);
        patientResult.Sim_LungVol_Std = round(Sim_Lung_Volume_Std_Dev, 4);
        patientResult.Sim_TransP_Mean = round(Sim_Transpulmonary_Pressure_Mean, 4);
        patientResult.Sim_TransP_Max = round(Sim_Transpulmonary_Pressure_Max, 4);
        patientResult.Sim_TransP_Std = round(Sim_Transpulmonary_Pressure_Std_Dev, 4);
        patientResult.Sim_AlvP_PeakMax = round(Sim_Alv_Pressure_Peak_Max, 4);
        patientResult.Sim_AlvP_PeakMin = round(Sim_Alv_Pressure_Peak_Min, 4);
        patientResult.Sim_Flow_PeakMax = round(Sim_Respiratory_Flow_Peak_Max, 4);
        patientResult.Sim_Flow_Std = round(Sim_Respiratory_Flow_Std_Dev, 4);
        patientResult.Sim_DeadFlow_PeakMax = round(Sim_Dead_Space_Flow_Peak_Max, 4);
        patientResult.Sim_DeadFlow_Std = round(Sim_Dead_Space_Flow_Std_Dev, 4);
        
        % Append to main results table
        if isempty(results)
            results = patientResult;
        else
            results = [results; patientResult];
        end
        
        fprintf('  Patient %d completed successfully.\n', patientIndex);
        
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
        
        if exist('LC', 'var')
            patientResult.LC = round(LC, 4);
            patientResult.TC = round(TC, 4);
            patientResult.CR = round(CR, 4);
            patientResult.PR = round(PR, 4);
        else
            patientResult.LC = NaN;
            patientResult.TC = NaN;
            patientResult.CR = NaN;
            patientResult.PR = NaN;
        end
        patientResult.Cs = round(Cs, 4);
        
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
       
        if isempty(results)
            results = patientResult;
        else
            results = [results; patientResult];
        end
        
        % Clear variables for next iteration
        clear LC TC CR PR
    end
end

%% Save results to CSV
writetable(results, outputFilename);
fprintf('\nBatch processing complete!\n');
fprintf('Results saved to: %s\n', outputFilename);

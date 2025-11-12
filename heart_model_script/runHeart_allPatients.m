%% runHeart_allPatients.m  (toolbox-free, no state leaks, HR-based last-beat window)
% Batch runner for all patients in CSV:
%  - For each row: reload defaults, apply mapping, simulate ~2 beats
%  - Extract metrics over the last tc seconds (tc = 60/HR) instead of findpeaks
%  - Save to heart_sim_results.csv (with inputs echoed for sanity)

clear; clc;

%% --- Robust project open (no cd required) ---
scriptDir = fileparts(mfilename('fullpath'));           % .../Scripts/Work
projRoot  = fileparts(fileparts(scriptDir));            % go up twice → project root
projPath  = fullfile(projRoot, 'HeartModel.prj');
assert(isfile(projPath), "HeartModel.prj not found at %s", projPath);
proj = openProject(projPath);

%% --- File setup ---
infile  = fullfile(proj.RootFolder, 'choc-data-all.csv');
outfile = fullfile(proj.RootFolder, 'heart_sim_results.csv');
T       = readtable(infile, 'PreserveVariableNames', true);
N       = height(T);
results = table();

mdlName = 'CardioVascularSystem';
mdlPath = fullfile(proj.RootFolder, "Models", mdlName + ".slx");
load_system(mdlPath);

function v = getv(T, name, idx, def)
% Safe getter: returns def if column missing or value missing
    if any(strcmp(name, T.Properties.VariableNames))
        val = T.(name)(idx);
        if iscell(val) && ~isempty(val), val = val{1}; end   % handle cell text
        if ismissing(val) || (isnumeric(val) && isempty(val))
            v = def;
        else
            v = val;
        end
    else
        v = def;
    end
end

function tf = asFlag(x)
% Normalize yes/true/1 → true
    if islogical(x), tf = x; return; end
    if isnumeric(x), tf = x > 0; return; end
    s = upper(string(x));
    tf = ismember(s, ["Y","YES","TRUE","1"]);
end


%% --- Loop patients ---
for patientIndex = 1:N
    try
        % Fresh defaults each loop (prevents state carryover)
        run(fullfile(proj.RootFolder,"Scripts","Initialization.m"));

        % ---- Pull inputs (be explicit; no exist(...) checks) ----
        BSA     = getv(T, 'BSA (m2)',          patientIndex, getv(T,'BSA',patientIndex, 1.70));
        HR      = getv(T, 'HR',                 patientIndex, 75);
        LVEDVi  = getv(T, 'LVEDVi (mL/m2)',     patientIndex, getv(T,'LVEDVi',patientIndex, NaN));
        LVESVi  = getv(T, 'LVESVi (mL/m2)',     patientIndex, getv(T,'LVESVi',patientIndex, NaN));
        RVEDVi  = getv(T, 'RVEDVi (mL/m2)',     patientIndex, getv(T,'RVEDVi',patientIndex, NaN));
        RVESVi  = getv(T, 'RVESVi (mL/m2)',     patientIndex, getv(T,'RVESVi',patientIndex, NaN));
        SBP     = getv(T, 'SBP',                patientIndex, NaN);
        DBP     = getv(T, 'DBP',                patientIndex, NaN);
        HI      = getv(T, 'Mean HI',            patientIndex, 2.5);
        IVCraw  = getv(T, 'IVC compression?',   patientIndex, 0);
        RVraw   = getv(T, 'RV compression?',    patientIndex, 0);
        IVCcomp = asFlag(IVCraw);
        RVcomp  = asFlag(RVraw);

        % Echo first few patients so you can verify variability
        if patientIndex <= 5
            fprintf('[%3d] HR=%g  BSA=%g  HI=%g  LVEDVi=%g  LVESVi=%g  RVEDVi=%g  RVESVi=%g  SBP/DBP=%g/%g  IVC=%d  RV=%d\n', ...
                patientIndex, HR, BSA, HI, LVEDVi, LVESVi, RVEDVi, RVESVi, SBP, DBP, IVCcomp, RVcomp);
        end

        % ---- Mapping (no variable leakage) ----
        % Initial chamber volumes from indexed values (mL)
        if ~isnan(LVEDVi) && ~isnan(LVESVi) && ~isnan(BSA)
            LVEDV = LVEDVi * BSA;    % mL
            LVESV = LVESVi * BSA;    % mL
            assignin('base','X120', LVEDV);   % initial LV volume
        else
            LVEDV = NaN; LVESV = NaN;
        end

        if ~isnan(RVEDVi) && ~isnan(BSA)
            RVEDV = RVEDVi * BSA;
            assignin('base','X60', RVEDV);    % initial RV volume
        else
            RVEDV = NaN;
        end

        % Heart timing from HR
        if ~isnan(HR) && HR > 0
            assignin('base','HeartRate', HR);
            tc = 60/HR;
            ts = 0.16 + 0.3*tc;
            assignin('base','tc', tc);
            assignin('base','ts', ts);
        else
            tc = evalin('base','tc');
        end

        % Optional arterial compliance scaling via SV/PP if BP + LV volumes exist
        if ~isnan(SBP) && ~isnan(DBP) && ~isnan(LVEDV) && ~isnan(LVESV)
            PP   = max(5, SBP - DBP);        % mmHg
            SVlv = max(1, LVEDV - LVESV);    % mL
            Cart = SVlv / PP;                % mmHg^-1·cm^3 (≈ mL/mmHg)
            C1 = evalin('base','C1'); C2 = evalin('base','C2');
            ratio = C1 / (C1 + C2 + eps);
            assignin('base','C1', ratio*Cart);
            assignin('base','C2', (1-ratio)*Cart);
        end

        % Thoracic/venous & pulmonary compliance scaling by HI
        mult = (~isnan(HI)) * max(0.5, 1 - 0.06*(HI - 2.5)) + (isnan(HI))*1.0;
        C3 = evalin('base','C3'); C4 = evalin('base','C4'); C5 = evalin('base','C5'); C6 = evalin('base','C6');
        assignin('base','C3', C3*(0.85*mult + 0.15));
        assignin('base','C4', C4*mult);
        assignin('base','C5', C5*mult);
        assignin('base','C6', C6*(0.9*mult + 0.1));

        % Resistance tweaks from compression flags (non-valvular)
        if IVCcomp
            assignin('base','R3', 1.2 * evalin('base','R3'));
            assignin('base','C3', 0.9 * evalin('base','C3'));
        end
        if RVcomp
            assignin('base','R6', 1.2 * evalin('base','R6'));
            assignin('base','C5', 0.9 * evalin('base','C5'));
        end

        % ---- Simulate (~2 beats) ----
        set_param(mdlName,'SignalLogging','on','StopTime', num2str(2*tc));
        out = sim(mdlName);

        % ---- Extract time window: last tc seconds ----
        names = out.logsout.getElementNames;

        % Pull Aortic Pressure for timing baseline
        if any(strcmp('Aortic Pressure', names))
            ap = out.logsout.getElement('Aortic Pressure').Values;
            t  = ap.Time;  tEnd = t(end);
            t0 = max(t(1), tEnd - tc);
            idx = (t >= t0);
        else
            % Fallback: try any signal for time base
            anyName = names{find(~cellfun(@isempty,names),1,'first')};
            ts = out.logsout.getElement(anyName).Values;
            t  = ts.Time; tEnd = t(end); t0 = max(t(1), tEnd - tc);
            idx = (t >= t0);
        end

        % ---- Metrics over last beat window ----
        SV = NaN; CO = NaN; AoP_mean = NaN; AoP_max = NaN; AoP_min = NaN;

        if any(strcmp('Aortic Pressure', names))
            ap = out.logsout.getElement('Aortic Pressure').Values;
            AoP_mean = mean(ap.Data(idx));
            AoP_max  = max(ap.Data(idx));
            AoP_min  = min(ap.Data(idx));
        end

        if any(strcmp('LVOF', names))
            lvof = out.logsout.getElement('LVOF').Values;     % cm^3/s
            SV   = trapz(lvof.Time(idx), lvof.Data(idx));     % mL/beat (≈ cm^3)
            CO   = SV * HR / 1000;                            % L/min
        end

        % ---- Record row (echo inputs too) ----
        r = table(patientIndex, BSA, HR, HI, LVEDVi, LVESVi, RVEDVi, RVESVi, SBP, DBP, ...
                  SV, CO, AoP_mean, AoP_max, AoP_min, ...
                  'VariableNames', {'patientIndex','BSA','HR','HI','LVEDVi','LVESVi','RVEDVi','RVESVi','SBP','DBP', ...
                                    'SV','CO','AoP_mean','AoP_max','AoP_min'});
        results = [results; r];

        if mod(patientIndex,25)==0 || patientIndex<=5
            fprintf('OK %d/%d  HR=%g  SV=%.1f mL  CO=%.2f L/min  AoPmean=%.1f\n', ...
                patientIndex, N, HR, SV, CO, AoP_mean);
        end

    catch ME
        warning('Patient %d failed: %s', patientIndex, ME.message);
        r = table(patientIndex, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                  NaN, NaN, NaN, NaN, NaN, ...
                  'VariableNames', {'patientIndex','BSA','HR','HI','LVEDVi','LVESVi','RVEDVi','RVESVi','SBP','DBP', ...
                                    'SV','CO','AoP_mean','AoP_max','AoP_min'});
        results = [results; r];
    end
end

writetable(results, outfile, 'Delimiter', ',');
fprintf('Saved: %s\n', outfile);

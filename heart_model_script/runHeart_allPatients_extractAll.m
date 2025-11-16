%% runHeart_allPatients.m
% Batch runner for all patients in CSV:
%  1) For each row: reload defaults, apply SAME mapping as runHeart_onePatient
%  2) Simulate ~2 beats
%  3) Extract SV / CO / AoP stats over the last tc seconds (tc = 60/HR)
%  4) Save metrics + key inputs to heart_sim_results.csv


% edited to extract all time series data
clear; clc;

%% --- Robust project open (no cd required) ---
scriptDir = fileparts(mfilename('fullpath'));           % .../Scripts/Work
projRoot  = fileparts(fileparts(scriptDir));            % go up twice → project root
projPath  = fullfile(projRoot, 'HeartModel.prj');
assert(isfile(projPath), "HeartModel.prj not found at %s", projPath);
proj = openProject(projPath);

%% --- File setup ---
infile  = fullfile(proj.RootFolder, 'choc-data-all-temp.csv');
outfile = fullfile(proj.RootFolder, 'heart_sim_results.csv');
outfile_full = fullfile(proj.RootFolder, 'all_patients_timeseries_extract.csv');


T       = readtable(infile, 'PreserveVariableNames', true);
N       = height(T);
results = table();

mdlName = 'CardioVascularSystem';
mdlPath = fullfile(proj.RootFolder, "Models", mdlName + ".slx");
load_system(mdlPath);

fprintf('Running heart simulation for %d patients...\n', N);


masterTable = table(); % table for extracting time series data


%% --- Loop patients ---
for patientIndex = 1:N
    try
        % Fresh defaults each loop (prevents state carryover)
        run(fullfile(proj.RootFolder,"Scripts","Initialization.m"));

        %% ---------- 1. PULL CORE FIELDS FROM CHOC TABLE ----------
        % BSA, volumes, BP, HI, compression flags
        BSA        = getv(T, 'BSA (m2)',          patientIndex, getv(T,'BSA',patientIndex, 1.7));
        HRmax      = getv(T, 'HR max',            patientIndex, NaN);
        HRmaxPct   = getv(T, 'HR max %predicted', patientIndex, NaN);
        HRcol      = getvFlex(T, {'HR'},          patientIndex, NaN);  % optional direct HR
        age        = getv(T, 'Age',               patientIndex, 16);   % reasonable teen default

        LVEDVi     = getv(T, 'LVEDVi (mL/m2)',    patientIndex, getv(T,'LVEDVi (M 56-104 F 55-95)', patientIndex, NaN));
        LVESVi     = getv(T, 'LVESVi (mL/m2)',    patientIndex, getv(T,'LVESVi (M 16-40 F 15-35)', patientIndex, NaN));
        RVEDVi     = getv(T, 'RVEDVi (mL/m2)',    patientIndex, getv(T,'RVEDVi (M 60-108 F 58-94)', patientIndex, NaN));
        RVESVi     = getv(T, 'RVESVi (mL/m2)',    patientIndex, getv(T,'RVESVi (M 18-46 F 17-37)', patientIndex, NaN));

        SBP        = getv(T, 'SBP',               patientIndex, NaN);
        DBP        = getv(T, 'DBP',               patientIndex, NaN);
        HI         = getv(T, 'Mean HI',           patientIndex, 2.5);

        IVCraw     = getv(T, 'IVC compression?',  patientIndex, 0);
        RVraw      = getv(T, 'RV compression?',   patientIndex, 0);

        IVCcomp    = asFlag(IVCraw);
        RVcomp     = asFlag(RVraw);

        % Optional Pt Key if present
        PtKey      = getvFlex(T, {'Pt Key','PtKey'}, patientIndex, NaN);

        %% ---------- 2. EXTRA FIELDS FOR R1/R4/R5/R6/RL/RR MAPPING ----------
        LVEF        = getvFlex(T, {'LVEF','LVEF%','LV EF %'},                       patientIndex, NaN);
        RVEF        = getvFlex(T, {'RVEF','RVEF%','RV EF %'},                       patientIndex, NaN);
        LVmassIdx   = getvFlex(T, {'LV mass index','LV Mass Index'},               patientIndex, NaN);
        Eesep       = getvFlex(T, {'E/e'' ratio (MV septal)','E/e septal','E/e'''}, patientIndex, NaN);
        O2PulsePct  = getvFlex(T, {'O2 Pulse %predicted','O2 pulse % predicted'},   patientIndex, NaN);
        VO2maxPct   = getvFlex(T, {'VO2 max %predicted','VO2max %predicted'},       patientIndex, NaN);
        CCI         = getvFlex(T, {'CCI','PMC'},                                   patientIndex, NaN);
        SternalTor  = getvFlex(T, {'Sternal Torsion Angle','Sternal torsion'},     patientIndex, NaN);
        RA_size     = getvFlex(T, {'RA size','RA area','RA volume'},               patientIndex, NaN);
        LA_size     = getvFlex(T, {'LA size','LA area','LA volume'},               patientIndex, NaN);

        %% ---------- 3. HEART RATE FROM HRmax / HRmax %PRED / HR COLUMN ----------
        if ~isnan(HRmax)
            HR = 0.6 * HRmax;
        elseif ~isnan(HRmaxPct)
            HRpredMax = 220 - age;
            HR = 0.6 * (HRmaxPct/100) * HRpredMax;
        elseif ~isnan(HRcol)
            HR = HRcol;
        else
            HR = 75;   % hard fallback
        end

        %% ---------- 4. MAP TO MODEL: INITIAL VOLUMES ----------
        if ~isnan(LVEDVi) && ~isnan(LVESVi) && ~isnan(BSA)
            LVEDV = LVEDVi * BSA;           % mL
            LVESV = LVESVi * BSA;           % mL
            assignin('base','X120', LVEDV); % initial LV volume
        else
            LVEDV = NaN; LVESV = NaN;
        end

        if ~isnan(RVEDVi) && ~isnan(BSA)
            RVEDV = RVEDVi * BSA;           % mL
            assignin('base','X60', RVEDV);  % initial RV volume
        else
            RVEDV = NaN;
        end

        %% ---------- 5. HEART TIMING (HR → tc, ts) ----------
        if ~isnan(HR) && HR > 0
            assignin('base','HeartRate', HR);
            tc = 60/HR; 
            ts = 0.16 + 0.3*tc;
            assignin('base','tc', tc);
            assignin('base','ts', ts);
        else
            tc = evalin('base','tc');   % from defaults
        end

        %% ---------- 6. ARTERIAL COMPLIANCE (C1, C2) FROM LV VOLUMES + BP ----------
        if ~isnan(SBP) && ~isnan(DBP) && ~isnan(LVEDV) && ~isnan(LVESV)
            PP   = max(5, SBP - DBP);               % mmHg
            SVlv = max(1, LVEDV - LVESV);           % mL
            Cart = SVlv / PP;                       % mmHg^-1·cm^3
            C1 = evalin('base','C1'); C2 = evalin('base','C2');
            frac = C1 / (C1 + C2 + eps);            % keep C1:C2 ratio
            assignin('base','C1', frac*Cart);
            assignin('base','C2', (1-frac)*Cart);
        end

        %% ---------- 7. HI-BASED THORACIC / VENOUS / PULMONARY COMPLIANCE (C3–C6) ----------
        mult = 1.0;
        if ~isnan(HI)
            mult = max(0.5, 1 - 0.06*(HI - 2.5));
        end
        C3 = evalin('base','C3'); C4 = evalin('base','C4'); 
        C5 = evalin('base','C5'); C6 = evalin('base','C6');
        assignin('base','C3', C3*(0.85*mult + 0.15));
        assignin('base','C4', C4*mult);
        assignin('base','C5', C5*mult);
        assignin('base','C6', C6*(0.9*mult + 0.1));

        %% ---------- 8. LOOP RESISTANCES FROM COMPRESSION FLAGS (R3, R6 + C3/C5) ----------
        if IVCcomp
            assignin('base','R3', 1.2 * evalin('base','R3'));
            assignin('base','C3', 0.9 * evalin('base','C3'));
        end
        if RVcomp
            assignin('base','R6', 1.2 * evalin('base','R6'));
            assignin('base','C5', 0.9 * evalin('base','C5'));
        end

        %% ---------- 9. VALVE RESISTANCES (R1, R4, R5, R8) ----------
        % R1: Aortic valve
        try
            if ~isnan(LVESVi) && ~isnan(LVEF)
                R1_0 = evalin('base','R1');
                loadFactor = clamp01((LVESVi - 40) / 40);       % 0 @ 40, ~1 @ 80
                efFactor   = clamp01((55 - LVEF) / 20);         % 0 @ 55, ~1 @ 35
                facR1      = 1 + 0.3*(0.6*loadFactor + 0.4*efFactor);
                assignin('base','R1', R1_0 * facR1);
            end
        catch
        end

        % R4, R5: pulmonary / RV-side valves
        try
            R4_0 = evalin('base','R4');
            R5_0 = evalin('base','R5');
            facValves = 1.0;

            if ~isnan(CCI) && CCI >= 2
                facValves = facValves * (1 + 0.25 * clamp01((CCI - 2) / 2));
            end
            if ~isnan(SternalTor)
                facValves = facValves * (1 + 0.3 * clamp01((SternalTor - 15) / 20));
            end
            if RVcomp
                facValves = facValves * 1.2;
            end

            facValves = min(max(facValves, 0.7), 2.0);
            assignin('base','R4', R4_0 * facValves);
            assignin('base','R5', R5_0 * facValves);
        catch
        end

        % R8: Mitral valve – from E/e'
        try
            if ~isnan(Eesep)
                R8_0 = evalin('base','R8');
                eeFactor = clamp01((Eesep - 10) / 15);
                facR8    = 1 + 0.2 * eeFactor;
                assignin('base','R8', R8_0 * facR8);
            end
        catch
        end

        %% ---------- 10. R6 (PULMONARY RESISTANCE) FROM RVEF / VO2max ----------
        try
            R6_0 = evalin('base','R6');
            fac6 = 1.0;

            if ~isnan(RVEF)
                efPulm = clamp01((55 - RVEF) / 20);
                fac6   = fac6 * (1 + 0.3 * efPulm);
            end
            if ~isnan(VO2maxPct)
                vo2Bad = clamp01((100 - VO2maxPct) / 40);
                fac6   = fac6 * (1 + 0.2 * vo2Bad);
            end

            fac6 = min(max(fac6, 0.7), 2.5);
            assignin('base','R6', R6_0 * fac6);
        catch
        end

        %% ---------- 11. MYOCARDIAL VISCOUS TERMS (RL, RR) ----------
        % RL: LV side
        try
            RL0 = evalin('base','RL');
            facRL = 1.0;

            if ~isnan(Eesep)
                stiffLV = clamp01((Eesep - 10) / 15);
                facRL   = facRL * (1 + 0.3 * stiffLV);
            end
            if ~isnan(LVmassIdx)
                hyperLV = clamp01((LVmassIdx - 80) / 60);
                facRL   = facRL * (1 + 0.3 * hyperLV);
            end
            if ~isnan(O2PulsePct)
                lowO2P  = clamp01((100 - O2PulsePct) / 40);
                facRL   = facRL * (1 + 0.3 * lowO2P);
            end

            facRL = min(max(facRL, 0.7), 3.0);
            assignin('base','RL', RL0 * facRL);
        catch
        end

        % RR: RV side
        try
            RR0 = evalin('base','RR');
            facRR = 1.0;

            if ~isnan(RVEF)
                stiffRV = clamp01((55 - RVEF) / 20);
                facRR   = facRR * (1 + 0.3 * stiffRV);
            end
            if ~isnan(O2PulsePct)
                lowO2P  = clamp01((100 - O2PulsePct) / 40);
                facRR   = facRR * (1 + 0.25 * lowO2P);
            end

            facRR = min(max(facRR, 0.7), 3.0);
            assignin('base','RR', RR0 * facRR);
        catch
        end

        %% ---------- 12. OPTIONAL: R7 (PULMONARY VENOUS SIDE) ----------
        try
            if ~isnan(Eesep) || ~isnan(LA_size)
                R7_0 = evalin('base','R7');
                fac7 = 1.0;
                if ~isnan(Eesep)
                    highLVfill = clamp01((Eesep - 10) / 15);
                    fac7 = fac7 * (1 + 0.25 * highLVfill);
                end
                if ~isnan(LA_size)
                    bigLA = clamp01((LA_size - 25) / 20);
                    fac7 = fac7 * (1 + 0.2 * bigLA);
                end
                fac7 = min(max(fac7, 0.7), 2.5);
                assignin('base','R7', R7_0 * fac7);
            end
        catch
        end

        %% ---------- 13. SIMULATE (~2 beats) ----------
        set_param(mdlName,'SignalLogging','on','StopTime', num2str(2*tc));
        out = sim(mdlName);
        names = out.logsout.getElementNames;
        

        % ------- Export simulation data ------
        want  = {'Aortic Pressure','Left Ventricular Pressure','Right Venous Atrial Pressure', ...
                 'Pulmonary Pressure','LVOF','RVOF','LVIF','RVIF'};
        want  = want(ismember(want, names));


        ts0 = out.logsout.getElement(want{1}).Values;
        pidx = repmat({patientIndex}, length(ts0.Time), 1);
        
        % initialize temp table for this patient
        Ttemp = table(pidx, ts0.Time(:),'VariableNames', {'Pt Key','Time'});
        % Loop through each desired signal
        for k = 1:numel(want)
            ts = out.logsout.getElement(want{k}).Values;
        
            % Force column vector
            data = ts.Data(:);
        
            % Create a valid variable name for the column
            varName = matlab.lang.makeValidName(want{k});
        
            % Add to table
            Ttemp.(varName) = data;
        end

        masterTable = [masterTable; Ttemp];

        %% ---------- 14. METRICS OVER LAST BEAT (tc seconds) ----------
        SV = NaN; CO = NaN; AoP_mean = NaN; AoP_max = NaN; AoP_min = NaN;

        if any(strcmp('Aortic Pressure', names))
            ap = out.logsout.getElement('Aortic Pressure').Values;
            t  = ap.Time;
            tEnd = t(end);
            t0 = max(t(1), tEnd - tc);
            idxWin = (t >= t0);

            AoP_mean = mean(ap.Data(idxWin));
            AoP_max  = max(ap.Data(idxWin));
            AoP_min  = min(ap.Data(idxWin));
        else
            % If AoP missing, use any signal for time base
            anyName = names{1};
            tsAny   = out.logsout.getElement(anyName).Values;
            t  = tsAny.Time;
            tEnd = t(end);
            t0 = max(t(1), tEnd - tc);
            idxWin = (t >= t0);
        end

        if any(strcmp('LVOF', names))
            lvof = out.logsout.getElement('LVOF').Values;
            SV   = trapz(lvof.Time(idxWin), lvof.Data(idxWin));  % mL/beat
            CO   = SV * HR / 1000;                               % L/min
        end

        %% ---------- 15. RECORD ROW ----------
        r = table(patientIndex, PtKey, BSA, HR, HI, LVEDVi, LVESVi, RVEDVi, RVESVi, ...
                  SBP, DBP, SV, CO, AoP_mean, AoP_max, AoP_min, ...
                  'VariableNames', {'patientIndex','PtKey','BSA','HR','HI', ...
                                    'LVEDVi','LVESVi','RVEDVi','RVESVi', ...
                                    'SBP','DBP','SV','CO','AoP_mean','AoP_max','AoP_min'});
        results = [results; r];

        if mod(patientIndex,10)==0 || patientIndex <= 3
            fprintf('OK %3d/%3d  PtKey=%g  HR=%5.1f  SV=%6.1f mL  CO=%5.2f L/min  AoPmean=%6.1f\n', ...
                patientIndex, N, PtKey, HR, SV, CO, AoP_mean);
        end

    catch ME
        warning('Patient %d failed: %s', patientIndex, ME.message);
        r = table(patientIndex, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                  NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
          'VariableNames', {'patientIndex','PtKey','BSA','HR','HI', ...
                            'LVEDVi','LVESVi','RVEDVi','RVESVi', ...
                            'SBP','DBP','SV','CO','AoP_mean','AoP_max','AoP_min'});
        results = [results; r];
    end
end

writetable(results, outfile, 'Delimiter', ',');
fprintf('Saved results to: %s\n', outfile);

writetable(masterTable, outfile_full, 'Delimiter', ',');
fprintf('Saved combined time series: %s\n', outfile_full);

%% ===== Local helper functions (MUST be at end of script) =====

function v = getv(T, name, idx, def)
% Safe getter from table T for column "name" and row idx; falls back to def
    if any(strcmp(name, T.Properties.VariableNames))
        v = T.(name)(idx);
        if iscell(v) && ~isempty(v), v = v{1}; end
        if ismissing(v) || (isnumeric(v) && isempty(v))
            v = def;
        end
    else
        v = def;
    end
end

function v = getvFlex(T, patterns, idx, def)
% Get value from the first column whose name == or contains any pattern.
% Returns def if not found or unusable.
    v = def;
    vars = string(T.Properties.VariableNames);
    for p = 1:numel(patterns)
        pat = string(patterns{p});
        j = find(vars == pat, 1);
        if isempty(j)
            j = find(contains(vars, pat, 'IgnoreCase', true), 1);
        end
        if ~isempty(j)
            col = T.(vars(j));
            if idx <= height(T)
                val = col(idx);
                if iscell(val), val = val{1}; end
                if isnumeric(val)
                    if ~(isnan(val) || isempty(val))
                        v = val;
                        return;
                    end
                else
                    num = str2double(string(val));
                    if ~isnan(num)
                        v = num;
                        return;
                    else
                        v = def;
                        return;
                    end
                end
            end
        end
    end
end

function tf = asFlag(x)
% Convert numeric/string/logical table entries into logical flags.
    if islogical(x), tf = x; return; end
    try
        if isnumeric(x), tf = x > 0; return; end
        s = upper(string(x));
        tf = ismember(s, ["Y","YES","TRUE","1"]);
    catch
        tf = false;
    end
end

function y = clamp01(x)
% Clamp to [0, 1]
    y = min(max(x,0),1);
end

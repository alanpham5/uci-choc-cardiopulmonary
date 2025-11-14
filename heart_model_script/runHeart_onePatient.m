%% runHeart_onePatient.m
% Single-patient run for the Simscape Cardiovascular model
% 1) Opens project & loads defaults
% 2) Reads one patient row from CSV
% 3) Applies documented parameter mapping from CHOC data -> model params
% 4) Simulates ~2 beats
% 5) Plots key signals + prints SV/CO/AoP

clear; clc;

%% --- Robust project open (no cd required) ---
scriptDir = fileparts(mfilename('fullpath'));           % .../Scripts/Work
projRoot  = fileparts(fileparts(scriptDir));            % go up twice → project root
projPath  = fullfile(projRoot, 'HeartModel.prj');
assert(isfile(projPath), "HeartModel.prj not found at %s", projPath);
proj = openProject(projPath);

% Load default initialization file (Healthy baseline)
run(fullfile(proj.RootFolder, "Scripts", "Initialization.m"));

%% --- User inputs ---
infile       = fullfile(proj.RootFolder, 'choc-data-all.csv');
patientIndex = 15;   % <--- change this as needed

%% --- Load data ---
T = readtable(infile, 'PreserveVariableNames', true);

%% ---------- 1. PULL CORE FIELDS FROM CHOC TABLE ----------
% BSA, volumes, BP, HI, compression flags
BSA        = getv(T, 'BSA (m2)',            patientIndex, getv(T,'BSA',patientIndex, 1.7));
HRmax      = getv(T, 'HR max',              patientIndex, NaN);
HRmaxPct   = getv(T, 'HR max %predicted',   patientIndex, NaN);
age        = getv(T, 'Age',                 patientIndex, 16);   % reasonable teen default

LVEDVi     = getv(T, 'LVEDVi (mL/m2)',      patientIndex, getv(T,'LVEDVi', patientIndex, NaN));
LVESVi     = getv(T, 'LVESVi (mL/m2)',      patientIndex, getv(T,'LVESVi', patientIndex, NaN));
RVEDVi     = getv(T, 'RVEDVi (mL/m2)',      patientIndex, getv(T,'RVEDVi', patientIndex, NaN));
RVESVi     = getv(T, 'RVESVi (mL/m2)',      patientIndex, getv(T,'RVESVi', patientIndex, NaN));

SBP        = getv(T, 'SBP',                 patientIndex, NaN);
DBP        = getv(T, 'DBP',                 patientIndex, NaN);
HI         = getv(T, 'Mean HI',             patientIndex, 2.5);

IVCraw     = getv(T, 'IVC compression?',    patientIndex, 0);
RVraw      = getv(T, 'RV compression?',     patientIndex, 0);

% Normalize compression flags to logical
IVCcomp    = asFlag(IVCraw);
RVcomp     = asFlag(RVraw);

%% ---------- 2. EXTRA FIELDS FOR R1/R4/R5/R6/RL/RR MAPPING ----------
% Use flexible lookup because header naming can vary a bit
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

%% ---------- 3. HEART RATE FROM HRmax / HRmax %PRED ----------
if ~isnan(HRmax)
    % Use ~60% of max HR as a crude "operating" HR for the model
    HR = 0.6 * HRmax;
elseif ~isnan(HRmaxPct)
    % Rebuild from %predicted if needed: predicted max ≈ 220 - age
    HRpredMax = 220 - age;
    HR = 0.6 * (HRmaxPct/100) * HRpredMax;
else
    HR = 75;   % hard fallback if nothing is available
end

%% ---------- 4. MAP TO MODEL: INITIAL VOLUMES ----------
% X120 — initial LV volume, X60 — initial RV volume
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
% Don't touch L1–L4 (inertances)
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
% Use SV/PP heuristic if we have LVEDV/LVESV + SBP/DBP
if ~isnan(SBP) && ~isnan(DBP) && ~isnan(LVEDV) && ~isnan(LVESV)
    PP   = max(5, SBP - DBP);               % mmHg
    SVlv = max(1, LVEDV - LVESV);           % mL
    Cart = SVlv / PP;                       % mmHg^-1·cm^3 (mL ≈ cm^3)
    C1 = evalin('base','C1'); C2 = evalin('base','C2');
    frac = C1 / (C1 + C2 + eps);            % keep C1:C2 ratio
    assignin('base','C1', frac*Cart);
    assignin('base','C2', (1-frac)*Cart);
end

%% ---------- 7. HI-BASED THORACIC / VENOUS / PULMONARY COMPLIANCE (C3–C6) ----------
% Higher HI → more chest compression → lower venous/pulmonary compliances
mult = 1.0;
if ~isnan(HI)
    % Map HI=2.5 -> 1.0, HI=12 -> ~0.5
    mult = max(0.5, 1 - 0.06*(HI - 2.5));
end
C3 = evalin('base','C3'); C4 = evalin('base','C4'); 
C5 = evalin('base','C5'); C6 = evalin('base','C6');
assignin('base','C3', C3*(0.85*mult + 0.15));
assignin('base','C4', C4*mult);
assignin('base','C5', C5*mult);
assignin('base','C6', C6*(0.9*mult + 0.1));

%% ---------- 8. LOOP RESISTANCES FROM COMPRESSION FLAGS (R3, R6 + matching C3/C5) ----------
% PE with IVC or RV compression → harder venous return + higher pulmonary vascular resistance
if IVCcomp
    assignin('base','R3', 1.2 * evalin('base','R3'));  % harder systemic venous return
    assignin('base','C3', 0.9 * evalin('base','C3'));  % less venous compliance
end
if RVcomp
    assignin('base','R6', 1.2 * evalin('base','R6'));  % ↑ pulmonary arteriolar load
    assignin('base','C5', 0.9 * evalin('base','C5'));  % ↓ pulmonary arterial compliance
end

%% ---------- 9. VALVE RESISTANCES (R1, R4, R5, R8) FROM TABLE HEURISTICS ----------
% R1: Aortic valve – use LV systolic function (LVESVi/LVEF) as a proxy
try
    if ~isnan(LVESVi) && ~isnan(LVEF)
        R1_0 = evalin('base','R1');
        % Higher LVESVi with low LVEF → worse forward ejection → slightly higher R1
        % Normalize: LVESVi ~ 30–80, LVEF ~ 35–65
        loadFactor = clamp01((LVESVi - 40) / 40);       % 0 @ 40, ~1 @ 80
        efFactor   = clamp01((55 - LVEF) / 20);         % 0 @ 55, ~1 @ 35
        facR1      = 1 + 0.3*(0.6*loadFactor + 0.4*efFactor);   % up to ~30% increase
        assignin('base','R1', R1_0 * facR1);
    end
catch
    % If R1 not present, silently skip
end

% R4, R5: Valve-level effects, strongly tied to sternal torsion, PMC/CCI, RV compression
try
    R4_0 = evalin('base','R4');
    R5_0 = evalin('base','R5');
    facValves = 1.0;

    % CCI / PMC = 2 or 3 → more severe concavity
    if ~isnan(CCI) && CCI >= 2
        facValves = facValves * (1 + 0.25 * clamp01((CCI - 2) / 2));  % up to ~25% ↑
    end

    % Sternal torsion angle – large angles → more twist on RV outflow / pulmonary valve
    if ~isnan(SternalTor)
        facValves = facValves * (1 + 0.3 * clamp01((SternalTor - 15) / 20)); % 0 @ 15°, +30% @ ~35°
    end

    % RV compression flag – direct compression of RVOT / pulmonary valve
    if RVcomp
        facValves = facValves * 1.2;
    end

    facValves = min(max(facValves, 0.7), 2.0);  % safety bounds
    assignin('base','R4', R4_0 * facValves);
    assignin('base','R5', R5_0 * facValves);
catch
    % If any of these params missing, skip
end

% R8: Mitral valve – keep tied mainly to LV filling pressure (E/e'), but small effect
try
    if ~isnan(Eesep)
        R8_0 = evalin('base','R8');
        % high E/e' → higher filling pressure → slightly higher R8
        eeFactor = clamp01((Eesep - 10) / 15);     % 0 @10, ~1 @25
        facR8    = 1 + 0.2 * eeFactor;
        assignin('base','R8', R8_0 * facR8);
    end
catch
end

%% ---------- 10. R6 (PULMONARY RESISTANCE) FROM RVEF / VO2max ----------
% Additional scaling beyond RV compression, based on RV performance
try
    R6_0 = evalin('base','R6');
    fac6 = 1.0;

    if ~isnan(RVEF)
        % Low RVEF → more pulmonary afterload
        efPulm = clamp01((55 - RVEF) / 20);      % 0 @55, ~1 @35
        fac6   = fac6 * (1 + 0.3 * efPulm);
    end

    if ~isnan(VO2maxPct)
        % Low VO2max %pred → more global cardiorespiratory limitation
        vo2Bad = clamp01((100 - VO2maxPct) / 40);  % 0 @100, ~1 @60
        fac6   = fac6 * (1 + 0.2 * vo2Bad);
    end

    fac6 = min(max(fac6, 0.7), 2.5);
    assignin('base','R6', R6_0 * fac6);
catch
end

%% ---------- 11. MYOCARDIAL VISCOUS TERMS (RL, RR) ----------
% RL: LV "stiffness" – E/e', LV mass index, O2 Pulse %pred
try
    RL0 = evalin('base','RL');
    facRL = 1.0;

    if ~isnan(Eesep)
        stiffLV = clamp01((Eesep - 10) / 15);       % high E/e' = stiff LV
        facRL   = facRL * (1 + 0.3 * stiffLV);
    end

    if ~isnan(LVmassIdx)
        hyperLV = clamp01((LVmassIdx - 80) / 60);   % higher LVMI → hypertrophy
        facRL   = facRL * (1 + 0.3 * hyperLV);
    end

    if ~isnan(O2PulsePct)
        lowO2P  = clamp01((100 - O2PulsePct) / 40); % low O2 pulse %pred → inefficient stroke work
        facRL   = facRL * (1 + 0.3 * lowO2P);
    end

    facRL = min(max(facRL, 0.7), 3.0);
    assignin('base','RL', RL0 * facRL);
catch
end

% RR: RV "stiffness" – RVEF%, O2 Pulse %pred
try
    RR0 = evalin('base','RR');
    facRR = 1.0;

    if ~isnan(RVEF)
        stiffRV = clamp01((55 - RVEF) / 20);        % lower RVEF → stiffer/less efficient RV
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

%% ---------- 12. OPTIONAL: R7 (PULMONARY VENOUS SIDE) FROM E/e' + LA size ----------
try
    if ~isnan(Eesep) || ~isnan(LA_size)
        R7_0 = evalin('base','R7');
        fac7 = 1.0;
        if ~isnan(Eesep)
            highLVfill = clamp01((Eesep - 10) / 15);
            fac7 = fac7 * (1 + 0.25 * highLVfill);
        end
        if ~isnan(LA_size)
            bigLA = clamp01((LA_size - 25) / 20);  % very rough scaling
            fac7 = fac7 * (1 + 0.2 * bigLA);
        end
        fac7 = min(max(fac7, 0.7), 2.5);
        assignin('base','R7', R7_0 * fac7);
    end
catch
end

%% ---------- 13. SIMULATE (~2 beats) ----------
mdlPath = fullfile(proj.RootFolder, "Models", "CardioVascularSystem.slx");
load_system(mdlPath);
set_param('CardioVascularSystem','SignalLogging','on','StopTime', num2str(2*tc));
out = sim('CardioVascularSystem');

%% ---------- 14. PLOT KEY SIGNALS ----------
names = out.logsout.getElementNames;
want  = {'Aortic Pressure','Left Ventricular Pressure','Right Venous Atrial Pressure', ...
         'Pulmonary Pressure','LVOF','RVOF','LVIF','RVIF'};
want  = want(ismember(want, names));

for k = 1:numel(want)
    ts = out.logsout.getElement(want{k}).Values;
    figure; plot(ts.Time, ts.Data); grid on
    title(want{k},'Interpreter','none'); xlabel('s');
    if contains(want{k},'Pressure','ignorecase',true)
        ylabel('mmHg');
    else
        ylabel('cm^3/s');
    end
end

%% ---------- 15. QUICK METRICS (LAST BEAT, NO TOOLBOXES) ----------
if all(ismember({'Left Ventricular Pressure','Aortic Pressure'}, names))
    lvp = out.logsout.getElement('Left Ventricular Pressure').Values;
    ap  = out.logsout.getElement('Aortic Pressure').Values;

    % Use last cardiac period based on HR (no findpeaks needed)
    HR_base = evalin('base','HeartRate');
    tc_base = 60 / HR_base;                         % seconds/beat
    t1 = lvp.Time(end);                             % end time
    t0 = max(lvp.Time(1), t1 - tc_base);            % start of last beat
    idx = (lvp.Time >= t0) & (lvp.Time <= t1);      % indices for last beat
    if nnz(idx) < 3
        % Fallback: use last half-second if sampling very short
        t0 = max(lvp.Time(1), t1 - 0.5);
        idx = (lvp.Time >= t0) & (lvp.Time <= t1);
    end

    SV = NaN; CO = NaN;
    if any(strcmp('LVOF', names))
        lvof = out.logsout.getElement('LVOF').Values;
        SV   = trapz(lvof.Time(idx), lvof.Data(idx));    % mL/beat
        CO   = SV * HR_base / 1000;                      % L/min
    end

    SBP_sim = max(ap.Data(idx)); 
    DBP_sim = min(ap.Data(idx));
    fprintf('SV=%.1f mL, CO=%.2f L/min, AoP≈%.0f/%.0f mmHg (SBP/DBP)\n', ...
            SV, CO, SBP_sim, DBP_sim);
end

disp('Run complete. Adjust mapping constants as needed and re-run.');

%% ===== Local helper functions =====
function v = getv(T, name, idx, def)
% Safe getter from table T for column "name" and row idx; falls back to def.
% - Unwraps cell arrays
% - Converts numeric-looking text to numbers
% - Leaves true text (like 'Y'/'N') alone for asFlag()

    v = def;

    if ~any(strcmp(name, T.Properties.VariableNames))
        return;  % column not found → def
    end

    col = T.(name);

    if idx > height(T)
        return;  % out of range → def
    end

    val = col(idx);

    % unwrap cellstr
    if iscell(val) && ~isempty(val)
        val = val{1};
    end

    % Missing or empty numeric → def
    if ismissing(val) || (isnumeric(val) && isempty(val))
        v = def;
        return;
    end

    % If already numeric, keep it
    if isnumeric(val)
        v = val;
        return;
    end

    % For char/string: try to parse as a number
    s = string(val);
    num = str2double(s);

    if ~isnan(num)
        % e.g. '120' → 120
        v = num;
        return;
    else
        % Non-numeric text like 'Y', 'N', etc. → keep original
        v = val;
        return;
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

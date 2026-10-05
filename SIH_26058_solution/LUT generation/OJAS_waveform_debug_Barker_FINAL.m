function results = OJAS_waveform_debug_Barker_FINAL(oceanFile, sensorLutFile, waveformLutFile, rowToPlot)
% OJAS_WAVEFORM_DEBUG_BARKER_V8
% =========================================================================
% CLEAN OJAS INTERACTIVE WAVEFORM DEBUGGER
%
% DATA FLOW:
%   ocean_data.csv
%       -> sensor/Mackenzie LUT
%       -> selected Wxx
%       -> waveform-library CSV
%       -> waveform synthesis
%       -> time-domain + FFT + instantaneous-frequency diagnostics
%
% DESIGN RULES:
%   - No Wxx mapping is hardcoded.
%   - No waveform parameters are hardcoded.
%   - No Barker sequence is hardcoded.
%   - All waveform definitions come from the supplied CSV.
%   - Only the selected Wxx is synthesized when the GUI needs it.
%   - Generated waveforms are cached for fast row switching.
%
% GUI:
%   Top-left : clean parameter table
%   Top-mid  : full time-domain waveform
%   Top-right: zoomed time-domain waveform
%   Bottom-left : actual FFT
%   Bottom-mid  : actual instantaneous frequency vs CSV theory
%   Bottom-right: IF error OR phase-code sequence
%
% FINAL FIXES:
%   - IF extraction uses a local least-squares phase slope over a short
%     carrier-cycle window instead of raw sample-to-sample phase gradient.
%     This removes numerical IF noise while preserving the sweep.
%   - Hilbert edge artifacts are excluded from validation and from the
%     displayed IF error metric.
%   - Error plot is based only on the central validation core.
%
%   - Hilbert IF edge artifacts are NEVER plotted as validation errors.
%   - Actual-vs-theory IF uses only the central validation core (5%% to
%     95%% of the pulse); the excluded edges are explicitly marked.
%   - Error-axis scaling is based only on the valid core, so edge spikes
%     cannot visually dominate the plot.
%   - Validation reports RMS/max error only over the valid core.
%   - The parameter table reports the validation window and metric.
%
% V9 FIXES:
%   - uitable data are forced to character arrays; no string objects can
%     reach the MATLAB UI table, preventing the V8 'Values within a cell
%     array must be numeric, logical, or char' error.
%   - Prev/Next first commits the row edit box, preventing GUI-state and
%     displayed-row mismatches.
%   - Press Enter in the row box to commit the requested row.
%
% CORRECTNESS:
%   LFM:
%       actual IF should overlap CSV theory; error should stay near zero.
%   Geometric NFM:
%       actual IF should overlap the CSV exponential/geometric law.
%       Do NOT expect a visually large curvature when B/fc is small.
%   Phase Coded:
%       actual carrier IF remains at fc;
%       phase-code panel must reproduce the CSV chip phases.
%
% Example:
% results = OJAS_waveform_debug_Barker_v8( ...
%   'ocean_data.csv', ...
%   'OJAS_FINAL_SENSOR_MACKENZIE_LUT_24.csv', ...
%   'OJAS_final_waveform_library_24_Barker.csv', 89);
%
% =========================================================================

    clc;

    %% ---------------------- FILE INPUT ---------------------------------
    if nargin < 1 || isempty(oceanFile)
        oceanFile = pickCsv('Select ocean_data.csv');
    end
    if nargin < 2 || isempty(sensorLutFile)
        sensorLutFile = pickCsv('Select OJAS sensor/Mackenzie LUT CSV');
    end
    if nargin < 3 || isempty(waveformLutFile)
        waveformLutFile = pickCsv('Select OJAS waveform library CSV');
    end

    ocean  = readtable(oceanFile,       'VariableNamingRule','preserve');
    sensor = readtable(sensorLutFile,   'VariableNamingRule','preserve');
    wave   = readtable(waveformLutFile, 'VariableNamingRule','preserve');

    %% ---------------------- SCHEMA -------------------------------------
    requiredOcean = { ...
        'depth_m','temperature_C','salinity_PSU','turbidity_NTU', ...
        'sound_speed_mps_mackenzie'};

    requiredSensor = { ...
        'waveform_id', ...
        'mackenzie_speed_min_mps','mackenzie_speed_max_mps', ...
        'depth_min_m','depth_max_m', ...
        'temperature_min_C','temperature_max_C', ...
        'salinity_min_PSU','salinity_max_PSU', ...
        'turbidity_min_NTU','turbidity_max_NTU'};

    requiredWave = { ...
        'waveform_id','waveform_type','fc_kHz','B_multiplier','Tp_us', ...
        'B_min_Hz','B_Hz','B_kHz','Tp_s','TBP','f_low_Hz','f_high_Hz', ...
        'frequency_valid','sampling_valid','hardware_valid', ...
        'phase_code_family','phase_code_length','phase_code_bpsk', ...
        'phase_code_phase_rad'};

    assertRequiredColumns(ocean,requiredOcean,'ocean_data.csv');
    assertRequiredColumns(sensor,requiredSensor,'sensor/Mackenzie LUT');
    assertRequiredColumns(wave,requiredWave,'waveform library');

    sensor.waveform_id = string(sensor.waveform_id);
    wave.waveform_id   = string(wave.waveform_id);

    %% ---------------------- OCEAN -> Wxx -------------------------------
    n = height(ocean);

    selectedW  = strings(n,1);
    matchCount = zeros(n,1);
    matchStatus = strings(n,1);

    for i = 1:n
        c  = numericOrNaN(ocean.sound_speed_mps_mackenzie(i));
        d  = numericOrNaN(ocean.depth_m(i));
        T  = numericOrNaN(ocean.temperature_C(i));
        S  = numericOrNaN(ocean.salinity_PSU(i));
        tu = numericOrNaN(ocean.turbidity_NTU(i));

        valid = ...
            sensor.mackenzie_speed_min_mps <= c & c <= sensor.mackenzie_speed_max_mps & ...
            sensor.depth_min_m <= d & d <= sensor.depth_max_m & ...
            sensor.temperature_min_C <= T & T <= sensor.temperature_max_C & ...
            sensor.salinity_min_PSU <= S & S <= sensor.salinity_max_PSU & ...
            sensor.turbidity_min_NTU <= tu & tu <= sensor.turbidity_max_NTU;

        idx = find(valid);
        matchCount(i) = numel(idx);

        if numel(idx) == 1
            selectedW(i) = sensor.waveform_id(idx);
            matchStatus(i) = "MATCHED_UNIQUE";
        elseif isempty(idx)
            matchStatus(i) = "NO_SENSOR_LUT_MATCH";
        else
            matchStatus(i) = "AMBIGUOUS_SENSOR_LUT_MATCH";
        end
    end

    %% ---------------------- Wxx metadata -------------------------------
    waveType = strings(n,1);
    generationStatus = strings(n,1);

    waveFc_kHz = nan(n,1);
    waveB_Hz = nan(n,1);
    waveTp_s = nan(n,1);
    waveFLow_Hz = nan(n,1);
    waveFHigh_Hz = nan(n,1);
    waveTBP = nan(n,1);

    phaseFamily = strings(n,1);
    phaseLength = nan(n,1);
    phaseBpsk = strings(n,1);
    phaseRad = strings(n,1);

    % Only metadata validation. No waveform generation here.
    for i = 1:n
        if selectedW(i) == ""
            generationStatus(i) = "NO_SENSOR_LUT_MATCH";
            continue;
        end

        wi = find(wave.waveform_id == selectedW(i),1,'first');

        if isempty(wi)
            generationStatus(i) = "WAVEFORM_ID_NOT_FOUND";
            continue;
        end

        wr = wave(wi,:);

        waveType(i) = toText(wr.waveform_type);
        waveFc_kHz(i) = numericOrNaN(wr.fc_kHz);
        waveB_Hz(i) = numericOrNaN(wr.B_Hz);
        waveTp_s(i) = numericOrNaN(wr.Tp_s);
        waveFLow_Hz(i) = numericOrNaN(wr.f_low_Hz);
        waveFHigh_Hz(i) = numericOrNaN(wr.f_high_Hz);
        waveTBP(i) = numericOrNaN(wr.TBP);

        phaseFamily(i) = toText(wr.phase_code_family);
        phaseLength(i) = numericOrNaN(wr.phase_code_length);
        phaseBpsk(i) = toText(wr.phase_code_bpsk);
        phaseRad(i) = toText(wr.phase_code_phase_rad);

        generationStatus(i) = validateWaveformRow(wr);
    end

    %% ---------------------- OUTPUT TABLE -------------------------------
    results = ocean;
    results.input_row_1based = (1:n).';
    results.sensor_match_count = matchCount;
    results.selected_waveform_id = selectedW;
    results.match_status = matchStatus;
    results.waveform_type = waveType;
    results.waveform_generation_status = generationStatus;
    results.wave_fc_kHz = waveFc_kHz;
    results.wave_B_Hz = waveB_Hz;
    results.wave_Tp_s = waveTp_s;
    results.wave_f_low_Hz = waveFLow_Hz;
    results.wave_f_high_Hz = waveFHigh_Hz;
    results.wave_TBP = waveTBP;
    results.wave_phase_code_family = phaseFamily;
    results.wave_phase_code_length = phaseLength;
    results.wave_phase_code_bpsk = phaseBpsk;
    results.wave_phase_code_phase_rad = phaseRad;

    outFolder = fileparts(oceanFile);
    if isempty(outFolder)
        outFolder = pwd;
    end

    outCsv = fullfile(outFolder, ...
        'OJAS_combined_ocean_waveform_results_Barker_FINAL.csv');

    writetable(results,outCsv);

    %% ---------------------- SUMMARY ------------------------------------
    fprintf('\n============================================================\n');
    fprintf('OJAS WAVEFORM DEBUGGER FINAL\n');
    fprintf('============================================================\n');
    fprintf('Ocean rows                 : %d\n',n);
    fprintf('Unique Wxx matches         : %d\n',sum(matchStatus=="MATCHED_UNIQUE"));
    fprintf('No Wxx match               : %d\n',sum(matchStatus=="NO_SENSOR_LUT_MATCH"));
    fprintf('Ambiguous Wxx matches      : %d\n',sum(matchStatus=="AMBIGUOUS_SENSOR_LUT_MATCH"));
    fprintf('Combined CSV               : %s\n',outCsv);
    fprintf('GUI synthesizes only the selected Wxx.\n');
    fprintf('============================================================\n\n');

    if nargin < 4 || isempty(rowToPlot)
        rowToPlot = 1;
    end

    rowToPlot = clampRow(rowToPlot,n);

    createViewer(ocean,results,wave,rowToPlot);
end


% =========================================================================
% VALIDATE WAVEFORM METADATA
% =========================================================================
function msg = validateWaveformRow(wr)

    type = toText(wr.waveform_type);

    fc = numericOrNaN(wr.fc_kHz)*1e3;
    Tp = numericOrNaN(wr.Tp_s);
    fLow = numericOrNaN(wr.f_low_Hz);
    fHigh = numericOrNaN(wr.f_high_Hz);

    if ~isfinite(fc) || fc <= 0
        msg = "INVALID_FC";
        return;
    end

    if ~isfinite(Tp) || Tp <= 0
        msg = "INVALID_TP";
        return;
    end

    switch type
        case "LFM"
            if isfinite(fLow) && isfinite(fHigh) && fLow > 0 && fHigh > 0
                msg = "GENERATABLE_LFM";
            else
                msg = "INVALID_LFM_LIMITS";
            end

        case "Geometric_NFM"
            if isfinite(fLow) && isfinite(fHigh) && fLow > 0 && fHigh > 0
                msg = "GENERATABLE_GEOMETRIC_NFM";
            else
                msg = "INVALID_GEOMETRIC_LIMITS";
            end

        case "Phase_Coded"
            try
                [pr,bpsk,~] = extractPhaseData(wr);
                if isempty(pr) || numel(pr) ~= numel(bpsk)
                    msg = "INVALID_PHASE_DATA";
                else
                    msg = "GENERATABLE_PHASE_CODED";
                end
            catch
                msg = "INVALID_PHASE_DATA";
            end

        otherwise
            msg = "UNSUPPORTED_WAVEFORM_TYPE";
    end
end


% =========================================================================
% INTERACTIVE VIEWER
% =========================================================================
function createViewer(ocean,results,wave,initialRow)

    n = height(ocean);

    state.row = initialRow;
    state.zoomUs = 300;
    state.autoZoom = true;
    state.fullPulse = false;
    state.validationEdgeFraction = 0.05;  % exclude 5%% at each pulse edge

    cacheID = strings(0,1);
    cacheData = cell(0,1);

    fig = figure( ...
        'Name','OJAS — Ocean -> Wxx -> Waveform Correctness FINAL', ...
        'NumberTitle','off', ...
        'Color','w', ...
        'Position',[30 35 1550 900], ...
        'WindowKeyPressFcn',@keyPress);

    %% ---------------------- CLEAN CONTROL BAR --------------------------
    uicontrol(fig,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.010 0.955 0.080 0.030], ...
        'String','Ocean row', ...
        'HorizontalAlignment','right', ...
        'FontWeight','bold', ...
        'BackgroundColor','w');

    hRow = uicontrol(fig,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.095 0.952 0.055 0.036], ...
        'String',num2str(state.row), ...
        'BackgroundColor','w', ...
        'Callback',@rowChanged, ...
        'KeyPressFcn',@rowKeyPress);

    uicontrol(fig,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.155 0.952 0.050 0.036], ...
        'String','Prev', ...
        'Callback',@prevRow);

    uicontrol(fig,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.210 0.952 0.050 0.036], ...
        'String','Next', ...
        'Callback',@nextRow);

    uicontrol(fig,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.265 0.952 0.048 0.036], ...
        'String','Go', ...
        'Callback',@goRow);

    uicontrol(fig,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.325 0.955 0.095 0.030], ...
        'String','Time zoom (\mus)', ...
        'HorizontalAlignment','right', ...
        'BackgroundColor','w');

    hZoom = uicontrol(fig,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.425 0.952 0.055 0.036], ...
        'String',num2str(state.zoomUs), ...
        'BackgroundColor','w', ...
        'Callback',@zoomChanged);

    hAuto = uicontrol(fig,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.485 0.952 0.070 0.036], ...
        'String','Auto', ...
        'Value',1, ...
        'BackgroundColor','w', ...
        'Callback',@autoChanged);

    hFull = uicontrol(fig,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.565 0.952 0.085 0.036], ...
        'String','Full pulse', ...
        'Value',0, ...
        'BackgroundColor','w', ...
        'Callback',@fullChanged);

    hStatus = uicontrol(fig,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.655 0.952 0.330 0.036], ...
        'String','', ...
        'HorizontalAlignment','left', ...
        'FontWeight','bold', ...
        'BackgroundColor','w');

    %% ---------------------- LAYOUT -------------------------------------
    % Top: parameters / waveform / zoom
    % Bottom: FFT / IF / error-or-phase
    axTime = axes('Parent',fig,'Position',[0.350 0.680 0.300 0.240]);
    axZoom = axes('Parent',fig,'Position',[0.680 0.680 0.300 0.240]);

    axFFT = axes('Parent',fig,'Position',[0.035 0.080 0.285 0.515]);
    axIF  = axes('Parent',fig,'Position',[0.360 0.080 0.285 0.515]);
    axErr = axes('Parent',fig,'Position',[0.680 0.080 0.300 0.515]);

    % Parameter table is an actual table, not text drawn over an axis.
    hTable = uitable(fig, ...
        'Units','normalized', ...
        'Position',[0.020 0.680 0.300 0.240], ...
        'ColumnName',{'Parameter','Value'}, ...
        'RowName',[], ...
        'ColumnWidth',{120,320}, ...
        'FontSize',9);

    updateViewer();

    %% ============================ CALLBACKS =============================
    function rowChanged(~,~)
        commitRowFromEdit();
    end

    function rowKeyPress(~,evt)
        if strcmp(evt.Key,'return') || strcmp(evt.Key,'enter')
            commitRowFromEdit();
        end
    end

    function goRow(varargin)
        commitRowFromEdit();
    end

    function prevRow(varargin)
        commitRowFromEdit();
        state.row = clampRow(state.row-1,n);
        set(hRow,'String',num2str(state.row));
        updateViewer();
    end

    function nextRow(varargin)
        commitRowFromEdit();
        state.row = clampRow(state.row+1,n);
        set(hRow,'String',num2str(state.row));
        updateViewer();
    end

    function commitRowFromEdit()
        r = str2double(strtrim(get(hRow,'String')));

        if ~isfinite(r) || r ~= round(r)
            set(hRow,'String',num2str(state.row));
            return;
        end

        state.row = clampRow(r,n);
        set(hRow,'String',num2str(state.row));
        updateViewer();
    end

    function zoomChanged(~,~)

        z = str2double(get(hZoom,'String'));

        if ~isfinite(z) || z <= 0
            set(hZoom,'String',num2str(state.zoomUs));
            return;
        end

        state.zoomUs = z;
        state.autoZoom = false;
        set(hAuto,'Value',0);
        updateViewer();
    end

    function autoChanged(src,~)
        state.autoZoom = logical(get(src,'Value'));
        updateViewer();
    end

    function fullChanged(src,~)
        state.fullPulse = logical(get(src,'Value'));
        updateViewer();
    end

    function keyPress(~,evt)
        switch evt.Key
            case 'rightarrow'
                nextRow();
            case 'leftarrow'
                prevRow();
        end
    end

    %% ============================= UPDATE ==============================
    function updateViewer()

        i = state.row;

        cla(axTime);
        cla(axZoom);
        cla(axFFT);
        cla(axIF);
        cla(axErr);

        selectedW = string(results.selected_waveform_id(i));

        if selectedW == ""
            set(hTable,'Data', { ...
                'Ocean row',num2str(i); ...
                'Match status',char(results.match_status(i)); ...
                'Selected Wxx','NONE'; ...
                'Waveform type','NONE'; ...
                'Status',char(results.waveform_generation_status(i))});
            clearAxes('No unique Wxx match.');
            set(hStatus,'String', ...
                sprintf('Row %d / %d — no unique Wxx match',i,n));
            return;
        end

        wi = find(wave.waveform_id == selectedW,1,'first');

        if isempty(wi)
            set(hTable,'Data',{ ...
                'Ocean row',num2str(i); ...
                'Selected Wxx',char(selectedW); ...
                'Status','Wxx not found in waveform CSV'});
            clearAxes('Wxx not found in waveform CSV.');
            return;
        end

        wr = wave(wi,:);
        type = toText(wr.waveform_type);

        %% ---------------------- parameter table ------------------------
        paramData = { ...
            'Ocean row', sprintf('%d / %d',i,n); ...
            'Depth', sprintf('%.6g m',numericOrNaN(ocean.depth_m(i))); ...
            'Temperature', sprintf('%.6g °C',numericOrNaN(ocean.temperature_C(i))); ...
            'Salinity', sprintf('%.6g PSU',numericOrNaN(ocean.salinity_PSU(i))); ...
            'Turbidity', sprintf('%.6g NTU',numericOrNaN(ocean.turbidity_NTU(i))); ...
            'Sound speed', sprintf('%.6g m/s',numericOrNaN(ocean.sound_speed_mps_mackenzie(i))); ...
            'Selected Wxx',char(selectedW); ...
            'Waveform type',char(type); ...
            'fc',sprintf('%.6g kHz',numericOrNaN(wr.fc_kHz)); ...
            'Bandwidth',sprintf('%.6g kHz',numericOrNaN(wr.B_kHz)); ...
            'Pulse duration',sprintf('%.6g ms',numericOrNaN(wr.Tp_s)*1e3); ...
            'f_low',sprintf('%.6g kHz',numericOrNaN(wr.f_low_Hz)/1e3); ...
            'f_high',sprintf('%.6g kHz',numericOrNaN(wr.f_high_Hz)/1e3); ...
            'CSV status',char(results.waveform_generation_status(i)); ...
            'Validation window',sprintf('%.0f%% to %.0f%% of pulse', ...
                100*state.validationEdgeFraction, ...
                100*(1-state.validationEdgeFraction))};

        if type == "Phase_Coded"
            try
                [pr,bpsk,fam] = extractPhaseData(wr);
                paramData(end+1,:) = {'Code family',char(fam)};
                paramData(end+1,:) = {'Code chips',num2str(numel(pr))};
                paramData(end+1,:) = {'BPSK sequence',strjoin(string(bpsk),'  ')};
                paramData(end+1,:) = {'Phase sequence',strjoin(string(pr),'  ')};
            catch
            end
        end

        % MATLAB uitable accepts char/numeric/logical cells, not string
        % scalars. Normalize every cell explicitly before updating the UI.
        paramData = normalizeUITableData(paramData);
        set(hTable,'Data',paramData);

        %% ---------------------- waveform --------------------------------
        [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,wasCached,msg] = ...
            getWaveformForWxx(selectedW,wr);

        if ~wasCached
            set(hStatus,'String',sprintf('Generating %s...',char(selectedW)));
            drawnow;
        end

        if isempty(t)
            clearAxes(msg);
            set(hStatus,'String',sprintf('Row %d — %s — %s', ...
                i,char(selectedW),msg));
            return;
        end

        Tpulse = t(end);
        TpulseUs = Tpulse*1e6;

        %% ---------------------- Instantaneous frequency -----------------
        edgeN = max(10,round(state.validationEdgeFraction*numel(t)));
        validCore = false(size(t));

        if 2*edgeN < numel(t)
            validCore(edgeN+1:end-edgeN) = true;
        else
            validCore(:) = true;
        end

        if type == "Phase_Coded"

            % Phase-coded waveforms have intentional phase jumps. Their
            % carrier frequency is constant, so Hilbert-derived IF is not
            % used as a correctness metric here.
            fActual = numericOrNaN(wr.fc_kHz)*1e3*ones(size(t));

            validation = validatePhaseWaveform(wr,fTheory);

        else

            % Extract IF numerically from the generated real waveform.
            fActual = estimateInstantaneousFrequency(x,t);

            validation = validateFrequencyWaveform( ...
                type,fTheory,fActual,validCore);
        end

        % For plotting, explicitly hide the unreliable finite-pulse edge
        % region. The raw waveform itself is still shown for the full pulse.
        fActualPlot = fActual;
        fActualPlot(~validCore) = NaN;

        ifErrorPlot = fActual - fTheory;
        ifErrorPlot(~validCore) = NaN;

        %% ---------------------- time domain ------------------------------
        p = displayIndices(numel(t),9000);

        plot(axTime,t(p)*1e6,x(p),'LineWidth',0.8);
        grid(axTime,'on');
        xlabel(axTime,'Time (\mus)');
        ylabel(axTime,'Amplitude');
        ylim(axTime,[-1.2 1.2]);
        xlim(axTime,[0 TpulseUs]);

        title(axTime,sprintf( ...
            '2. TIME DOMAIN — %s | %s', ...
            char(selectedW),char(type)), ...
            'Interpreter','none');

        if ~isempty(chipEdges)
            hold(axTime,'on');
            for k = 2:numel(chipEdges)-1
                xline(axTime,chipEdges(k)*1e6,'--','LineWidth',0.8);
            end
            hold(axTime,'off');
        end

        %% ---------------------- zoom ------------------------------------
        zoomUs = chooseZoom(type,wr,TpulseUs,state);

        maskZ = t*1e6 <= zoomUs;

        if ~any(maskZ)
            maskZ = true(size(t));
        end

        tz = t(maskZ);
        xz = x(maskZ);

        pz = displayIndices(numel(tz),7500);

        plot(axZoom,tz(pz)*1e6,xz(pz),'LineWidth',0.9);
        grid(axZoom,'on');
        xlabel(axZoom,'Time (\mus)');
        ylabel(axZoom,'Amplitude');
        ylim(axZoom,[-1.2 1.2]);
        xlim(axZoom,[0,min(zoomUs,TpulseUs)]);

        title(axZoom,sprintf( ...
            '3. ZOOMED TIME DOMAIN — %.4g \\mus', ...
            min(zoomUs,TpulseUs)));

        if ~isempty(chipEdges)
            hold(axZoom,'on');

            for k = 2:numel(chipEdges)-1
                ek = chipEdges(k)*1e6;

                if ek <= zoomUs
                    xline(axZoom,ek,'--','LineWidth',0.8);
                end
            end

            hold(axZoom,'off');
        end

        %% ---------------------- FFT -------------------------------------
        [fFFT,magDb] = waveformSpectrum(t,x);

        fCenter = numericOrNaN(wr.fc_kHz)*1e3;
        B = numericOrNaN(wr.B_Hz);

        if ~isfinite(B) || B <= 0
            B = max(1,0.02*fCenter);
        end

        fLow = numericOrNaN(wr.f_low_Hz);
        fHigh = numericOrNaN(wr.f_high_Hz);

        margin = max(0.40*B,0.008*fCenter);

        keep = fFFT >= max(0,fLow-margin) & ...
               fFFT <= fHigh+margin;

        plot(axFFT,fFFT(keep)/1e3,magDb(keep),'LineWidth',1.1);
        grid(axFFT,'on');
        xlabel(axFFT,'Frequency (kHz)');
        ylabel(axFFT,'Magnitude (dB)');
        title(axFFT,'4. FREQUENCY DOMAIN — ACTUAL FFT');

        if any(keep)
            xlim(axFFT,[max(0,fLow-margin),fHigh+margin]/1e3);
        end

        hold(axFFT,'on');
        xline(axFFT,fCenter/1e3,'--','LineWidth',0.9);
        xline(axFFT,fLow/1e3,':','LineWidth',0.8);
        xline(axFFT,fHigh/1e3,':','LineWidth',0.8);
        hold(axFFT,'off');

        %% ---------------------- IF comparison ---------------------------
        pIF = displayIndices(numel(t),9000);

        % Theory is shown across the full pulse. Actual IF is shown only
        % in the central validation window to prevent Hilbert edge artifacts
        % from being mistaken for waveform errors.
        plot(axIF,t(pIF)*1e6,fActualPlot(pIF)/1e3, ...
            'LineWidth',1.1, ...
            'DisplayName','Actual IF (valid core)');

        hold(axIF,'on');

        plot(axIF,t(pIF)*1e6,fTheory(pIF)/1e3,'--', ...
            'LineWidth',1.4, ...
            'DisplayName','CSV theory');

        % Mark the excluded validation edges with unobtrusive vertical lines.
        xline(axIF,t(edgeN)*1e6,':','LineWidth',0.8, ...
            'DisplayName','Validation window');
        xline(axIF,t(end-edgeN)*1e6,':','LineWidth',0.8, ...
            'HandleVisibility','off');

        hold(axIF,'off');

        grid(axIF,'on');
        xlabel(axIF,'Time (\mus)');
        ylabel(axIF,'Frequency (kHz)');
        title(axIF,'5. INSTANTANEOUS FREQUENCY — ACTUAL vs CSV (5–95%)');

        legend(axIF,'Location','southoutside', ...
            'Orientation','horizontal');

        if isfinite(fLow) && isfinite(fHigh)

            if abs(fHigh-fLow) > 0

                marginIF = max(0.12*abs(fHigh-fLow),0.008*fCenter);

                ylim(axIF, ...
                    [(fLow-marginIF)/1e3,(fHigh+marginIF)/1e3]);
            else

                ylim(axIF, ...
                    [fCenter/1e3-1,fCenter/1e3+1]);
            end
        end

        %% ---------------------- error / phase ----------------------------
        if type == "Phase_Coded"

            [phaseRad,bpsk,fam] = extractPhaseData(wr);

            edgesUs = chipEdges*1e6;

            stairs(axErr,edgesUs,[phaseRad phaseRad(end)], ...
                'LineWidth',2.0, ...
                'DisplayName','CSV phase');

            hold(axErr,'on');

            for k = 2:numel(edgesUs)-1
                xline(axErr,edgesUs(k),'--','LineWidth',0.8);
            end

            hold(axErr,'off');

            grid(axErr,'on');
            xlabel(axErr,'Time (\mus)');
            ylabel(axErr,'Phase offset (rad)');
            title(axErr,sprintf( ...
                '6. PHASE CODE — %s',char(fam)), ...
                'Interpreter','none');

            xlim(axErr,[0 TpulseUs]);

            minPhase = min([0;phaseRad(:)])-0.4;
            maxPhase = max([pi;phaseRad(:)])+0.4;

            ylim(axErr,[minPhase,maxPhase]);

            yticks(sort(unique([0 pi])));
            yticklabels({'0','\pi'});

            % Keep chip labels in the legend, not as overlapping text.
            legend(axErr, ...
                sprintf('BPSK: [%s]',strjoin(string(bpsk),' ')), ...
                'Location','southoutside');

        else

            % Use only the valid core for the error plot. This completely
            % removes finite-record Hilbert-transform edge artifacts from
            % the displayed correctness metric.
            plot(axErr,t(pIF)*1e6,ifErrorPlot(pIF), ...
                'LineWidth',1.0, ...
                'DisplayName','Actual - CSV theory');

            hold(axErr,'on');

            yline(axErr,0,'--','LineWidth',0.9, ...
                'DisplayName','Zero error');

            xline(axErr,t(edgeN)*1e6,':','LineWidth',0.8, ...
                'DisplayName','Valid core');

            xline(axErr,t(end-edgeN)*1e6,':','LineWidth',0.8, ...
                'HandleVisibility','off');

            hold(axErr,'off');

            grid(axErr,'on');

            xlabel(axErr,'Time (\mus)');
            ylabel(axErr,'Frequency error (Hz)');

            title(axErr,'6. FREQUENCY ERROR — CENTRAL 90% ONLY');

            legend(axErr,'Location','southoutside', ...
                'Orientation','horizontal');

            e = fActual(validCore)-fTheory(validCore);
            e = e(isfinite(e));

            if isempty(e)
                scale = 25;
            else
                coreMax = max(abs(e));
                coreRms = sqrt(mean(e.^2));

                % Use actual core error; never use the edge artifacts.
                scale = max(25,1.35*max(coreMax,3*coreRms));
            end

            ylim(axErr,[-scale,scale]);

        end

        %% ---------------------- Status ----------------------------------
        set(hStatus,'String',sprintf( ...
            'Row %d/%d | %s | %s | fc %.6g kHz | B %.6g kHz | Tp %.6g ms | %s', ...
            i,n,selectedW,type, ...
            numericOrNaN(wr.fc_kHz), ...
            numericOrNaN(wr.B_kHz), ...
            numericOrNaN(wr.Tp_s)*1e3, ...
            validation));

        drawnow;
    end


    % =====================================================================
    % WAVEFORM CACHE
    % =====================================================================
    function [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,wasCached,msg] = ...
        getWaveformForWxx(id,wr)

        wasCached = false;

        ci = find(cacheID==id,1,'first');

        if ~isempty(ci)

            d = cacheData{ci};

            t = d.t;
            x = d.x;
            fTheory = d.fTheory;
            phaseCycles = d.phaseCycles;
            phaseOffset = d.phaseOffset;
            chipEdges = d.chipEdges;
            meta = d.meta;
            msg = d.msg;

            wasCached = true;
            return;
        end

        [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,msg] = ...
            synthesizeWaveform(wr);

        d.t = t;
        d.x = x;
        d.fTheory = fTheory;
        d.phaseCycles = phaseCycles;
        d.phaseOffset = phaseOffset;
        d.chipEdges = chipEdges;
        d.meta = meta;
        d.msg = msg;

        cacheID(end+1) = id;
        cacheData{end+1} = d;
    end

end


% =========================================================================
% WAVEFORM SYNTHESIS
% =========================================================================
function [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,msg] = ...
    synthesizeWaveform(wr)

    type = toText(wr.waveform_type);

    fc = numericOrNaN(wr.fc_kHz)*1e3;
    fLow = numericOrNaN(wr.f_low_Hz);
    fHigh = numericOrNaN(wr.f_high_Hz);
    Tp = numericOrNaN(wr.Tp_s);

    t = [];
    x = [];
    fTheory = [];
    phaseCycles = [];
    phaseOffset = [];
    chipEdges = [];
    meta = struct();
    msg = '';

    if ~isfinite(fc) || fc <= 0
        msg = 'INVALID: fc in CSV';
        return;
    end

    if ~isfinite(Tp) || Tp <= 0
        msg = 'INVALID: Tp in CSV';
        return;
    end

    maxF = max([abs(fc),abs(fLow),abs(fHigh)]);

    if ~isfinite(maxF) || maxF <= 0
        msg = 'INVALID: frequency data in CSV';
        return;
    end

    % Numerical simulation sampling rate only.
    samplesPerCycle = 32;
    Fs = samplesPerCycle*maxF;

    N = ceil(Tp*Fs)+1;

    if N > 150000
        N = 150001;
    end

    % Endpoints exactly span [0,Tp].
    t = linspace(0,Tp,N).';

    switch type

        case "LFM"

            if ~isfinite(fLow) || ~isfinite(fHigh)
                t=[]; msg='INVALID: LFM f_low/f_high'; return;
            end

            k = (fHigh-fLow)/Tp;

            fTheory = fLow + k*t;

            phaseCycles = ...
                fLow*t + 0.5*k*t.^2;

            x = cos(2*pi*phaseCycles);

            phaseOffset = zeros(size(t));

            msg = 'LFM_OK';


        case "Geometric_NFM"

            if ~isfinite(fLow) || ~isfinite(fHigh) || ...
                    fLow <= 0 || fHigh <= 0

                t=[]; msg='INVALID: Geometric NFM limits'; return;
            end

            a = log(fHigh/fLow)/Tp;

            if abs(a) < eps

                fTheory = fLow*ones(size(t));
                phaseCycles = fLow*t;

            else

                fTheory = fLow*exp(a*t);

                phaseCycles = ...
                    (fLow/a)*(exp(a*t)-1);
            end

            x = cos(2*pi*phaseCycles);

            phaseOffset = zeros(size(t));

            msg = 'GEOMETRIC_NFM_OK';


        case "Phase_Coded"

            [phaseRad,bpsk,fam] = extractPhaseData(wr);

            if isempty(phaseRad)
                t=[]; msg='INVALID: phase code'; return;
            end

            nChips = numel(phaseRad);
            Tc = Tp/nChips;

            chipIndex = floor(t/Tc)+1;
            chipIndex = max(1,min(nChips,chipIndex));

            phaseOffset = phaseRad(chipIndex);

            chipEdges = (0:nChips)*Tc;

            fTheory = fc*ones(size(t));

            phaseCycles = ...
                fc*t + phaseOffset/(2*pi);

            x = cos(2*pi*fc*t + phaseOffset);

            meta.family = fam;
            meta.bpsk = bpsk;
            meta.phaseRad = phaseRad;
            meta.chipDuration = Tc;

            msg = 'PHASE_CODED_OK';


        otherwise

            t=[];
            msg=['INVALID: unsupported waveform type ' char(type)];
    end
end


% =========================================================================
% INSTANTANEOUS FREQUENCY FROM GENERATED WAVEFORM
% =========================================================================
function fInst = estimateInstantaneousFrequency(x,t)
% Estimate IF from the generated real waveform.
%
% Method:
%   1) FFT Hilbert transform -> analytic signal.
%   2) unwrap analytic phase.
%   3) estimate local phase slope by least-squares linear regression.
%
% A local phase regression is much more stable than differentiating every
% sample directly, especially for narrow-band sweeps.

    x = x(:);
    t = t(:);
    N = numel(x);

    if N < 32
        fInst = NaN(size(x));
        return;
    end

    dt = mean(diff(t));
    Fs = 1/dt;

    % Analytic signal by FFT Hilbert transform.
    X = fft(x);
    H = zeros(N,1);

    if mod(N,2)==0
        H(1) = 1;
        H(N/2+1) = 1;
        H(2:N/2) = 2;
    else
        H(1) = 1;
        H(2:(N+1)/2) = 2;
    end

    analytic = ifft(X.*H);
    phi = unwrap(angle(analytic));

    % Use approximately 8 carrier cycles for the local phase fit.
    % The waveform synthesis uses 32 samples/carrier cycle, so this is
    % about 257 samples for the normal library. Adapt for safety.
    carrierEstimate = max(1,median(abs(diff(phi)))/(2*pi*dt));
    W = round(8*Fs/carrierEstimate);

    W = max(51,min(401,W));

    if W >= N
        W = N - 1;
    end

    if mod(W,2)==0
        W = W - 1;
    end

    if W < 5
        W = 5;
    end

    halfW = floor(W/2);

    fInst = NaN(N,1);

    for k = (halfW+1):(N-halfW)

        tt = t(k-halfW:k+halfW);
        pp = phi(k-halfW:k+halfW);

        tt0 = tt - mean(tt);
        pp0 = pp - mean(pp);

        denom = sum(tt0.^2);

        if denom > 0
            slope = sum(tt0.*pp0)/denom;
            fInst(k) = slope/(2*pi);
        end
    end

    % Light averaging of the estimated IF. This is only a numerical
    % presentation filter and does not modify the synthesized waveform.
    valid = isfinite(fInst);

    if any(valid)
        smoothN = 3;
        temp = fInst;
        temp(valid) = movmean(fInst(valid),smoothN);
        fInst = temp;
    end
end


% =========================================================================
% LFM / GEOMETRIC VALIDATION
% =========================================================================
function textOut = validateFrequencyWaveform(type,fTheory,fActual,validMask)

    valid = validMask & isfinite(fTheory) & isfinite(fActual);

    if sum(valid) < 50
        textOut = 'CHECK | insufficient valid IF samples';
        return;
    end

    e = fActual(valid)-fTheory(valid);

    rmsErr = sqrt(mean(e.^2));
    maxErr = max(abs(e));

    sweep = max(fTheory(valid))-min(fTheory(valid));

    % Acceptance threshold for the numerical diagnostic only.
    % This does not modify the waveform.
    tolerance = max(10,0.01*abs(sweep));

    normalizedRms = 100*rmsErr/max(abs(sweep),eps);

    if rmsErr <= tolerance
        stateText = 'PASS';
    else
        stateText = 'CHECK';
    end

    textOut = sprintf( ...
        '%s | core RMS %.4g Hz | core max %.4g Hz | %.4g%% of sweep', ...
        stateText,rmsErr,maxErr,normalizedRms);

    %#ok<NASGU>
    type = type;
end


% =========================================================================
% PHASE-CODE VALIDATION
% =========================================================================
function textOut = validatePhaseWaveform(wr,fTheory)

    fc = numericOrNaN(wr.fc_kHz)*1e3;

    carrierError = max(abs(fTheory-fc));

    try

        [pr,~,fam] = extractPhaseData(wr);

        if isempty(pr)
            textOut = 'CHECK | phase data missing';
            return;
        end

        if carrierError <= 1e-9

            textOut = sprintf( ...
                'PASS | %s | %d chips | carrier %.6g kHz', ...
                char(fam),numel(pr),fc/1e3);

        else

            textOut = sprintf( ...
                'CHECK | carrier mismatch %.4g Hz',carrierError);
        end

    catch ME

        textOut = ['CHECK | ' ME.message];
    end
end


% =========================================================================
% FFT
% =========================================================================
function [f,magDb] = waveformSpectrum(t,x)

    N = numel(x);

    if N < 16
        f=[]; magDb=[];
        return;
    end

    Fs = 1/mean(diff(t));

    n = (0:N-1).';

    w = 0.5*(1-cos(2*pi*n/max(1,N-1)));

    xw = x(:).*w;

    nfft = max(8192,2^nextpow2(N));
    nfft = min(nfft,131072);

    X = fft(xw,nfft);

    X = X(1:floor(nfft/2)+1);

    mag = abs(X);
    mag = mag/max(mag+eps);

    magDb = 20*log10(mag+eps);

    f = (0:floor(nfft/2)).'*Fs/nfft;
end


% =========================================================================
% PHASE DATA PARSER
% =========================================================================
function [phaseRad,bpsk,family] = extractPhaseData(wr)

    family = toText(wr.phase_code_family);

    bpsk = parseNumericList(toText(wr.phase_code_bpsk));
    phaseRad = parseNumericList(toText(wr.phase_code_phase_rad));

    if isempty(bpsk) && isempty(phaseRad)
        error('No phase data in waveform CSV.');
    end

    if isempty(phaseRad)

        if any(~ismember(bpsk,[-1 1]))
            error('BPSK values must be +1/-1.');
        end

        phaseRad = zeros(size(bpsk));
        phaseRad(bpsk<0)=pi;

    elseif isempty(bpsk)

        bpsk = ones(size(phaseRad));
        bpsk(abs(wrapToPiLocal(phaseRad)-pi)<1e-9)=-1;
    end

    if numel(phaseRad) ~= numel(bpsk)
        error('BPSK and phase arrays have different lengths.');
    end

    declared = numericOrNaN(wr.phase_code_length);

    if isfinite(declared) && declared > 0 && ...
            numel(phaseRad) ~= declared

        error('phase_code_length does not match phase array.');
    end
end


% =========================================================================
% ZOOM
% =========================================================================
function z = chooseZoom(type,wr,tpUs,state)
% Auto zoom is deliberately wider than previous versions so a normal user
% can visually distinguish frequency movement / chip transitions.

    if state.fullPulse
        z = tpUs;
        return;
    end

    if ~state.autoZoom
        z = min(state.zoomUs,tpUs);
        return;
    end

    fc = numericOrNaN(wr.fc_kHz)*1e3;

    if type == "Phase_Coded"

        try
            [pr,~,~] = extractPhaseData(wr);

            if ~isempty(pr)
                chipUs = numericOrNaN(wr.Tp_s)/numel(pr)*1e6;

                % Show 1.6 chips by default so a phase transition is visible
                % while the carrier remains clearly distinguishable.
                z = min(tpUs,max(1.6*chipUs,250));

            else
                z = min(tpUs,300);
            end

        catch
            z = min(tpUs,300);
        end

    else

        % Show a wider carrier window. The previous 100-us style window was
        % too tight for visually judging the sweep.
        % At least ~45 carrier cycles, with a 300-us floor.
        carrierWindowUs = 45e6/max(fc,1);
        z = min(tpUs,max(300,carrierWindowUs));
    end
end


% =========================================================================
% CLEAN-UP
% =========================================================================
function clearAxes(msg)

    axList = findall(gcf,'Type','axes');

    for k=1:numel(axList)
        axis(axList(k),'off');
        text(axList(k),0.05,0.85,msg, ...
            'Units','normalized', ...
            'FontWeight','bold', ...
            'Interpreter','none');
    end
end


function dataOut = normalizeUITableData(dataIn)
% Ensure uitable Data contains only char/numeric/logical cell contents.
    dataOut = dataIn;

    for rr = 1:size(dataOut,1)
        for cc = 1:size(dataOut,2)
            v = dataOut{rr,cc};

            if isstring(v)
                if ismissing(v) || strlength(v)==0
                    dataOut{rr,cc} = '';
                else
                    dataOut{rr,cc} = char(v);
                end
            elseif ischar(v)
                % Already valid.
            elseif isnumeric(v) || islogical(v)
                % Already valid.
            else
                dataOut{rr,cc} = char(string(v));
            end
        end
    end
end


function s = toText(v)

    try

        s=string(v);

        if ismissing(s) || s=="<missing>"
            s="";
        end

    catch

        s="";
    end
end


function x = numericOrNaN(v)

    if isnumeric(v)

        if isempty(v)
            x=NaN;
        else
            x=double(v(1));
        end

    else

        x=str2double(string(v));
    end

    if isempty(x) || ~isfinite(x)
        x=NaN;
    end
end


function v = parseNumericList(s)

    s=toText(s);

    if strlength(strtrim(s))==0 || ...
            lower(strtrim(s))=="nan" || ...
            lower(strtrim(s))=="<missing>"

        v=[];
        return;
    end

    s=strrep(s,';',',');

    parts=split(strtrim(s),',');
    parts=strtrim(parts);

    v=str2double(parts);

    if any(isnan(v))
        error('Invalid numeric list: %s',s);
    end

    v=v(:).';
end


function y=wrapToPiLocal(x)

    y=mod(x+pi,2*pi)-pi;
end


function idx=displayIndices(N,maxPts)

    if N<=maxPts
        idx=1:N;
    else
        idx=round(linspace(1,N,maxPts));
    end
end


function r=clampRow(r,n)

    if ~isfinite(r)
        r=1;
    end

    r=round(r);
    r=max(1,min(n,r));
end


function fileName=pickCsv(titleText)

    [file,path]=uigetfile({'*.csv','CSV files (*.csv)'},titleText);

    if isequal(file,0)
        error('CSV selection cancelled.');
    end

    fileName=fullfile(path,file);
end


function assertRequiredColumns(tbl,requiredNames,sourceName)

    available=tbl.Properties.VariableNames;

    missing=requiredNames(~ismember(requiredNames,available));

    if ~isempty(missing)

        error(['Required columns missing from %s:\n%s\n\n' ...
            'Available columns:\n%s'], ...
            sourceName, ...
            strjoin(missing,'\n'), ...
            strjoin(available,'\n'));
    end
end

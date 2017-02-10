function mousetimer()
%MOUSETIMER Time your mouse
clear all;

%Check to see if the video_logs folder exists
if exist('data_logs','dir') ~= 7
    mkdir('data_logs');
end

%Create the main program window
hFig = figure('Toolbar', 'none', 'Menubar', 'none','NumberTitle','Off', ...
    'Name','Mousetimer v0.1','DeleteFcn',{@delete_figure},...
    'KeyPressFcn',{@key_down},'Resize','Off',...
    'Position',[100 100 1040 600]);

%Partition 80% of the window for the video
subplot('Position',[0 0.05 0.8 0.9]);

axis off;

%Get info on the video sources
vid_info = imaqhwinfo('winvideo');

%How many cameras are there?
num_sources = length(vid_info.DeviceIDs);
lst_str=cell(1,num_sources);

%List available cameras
for i = 1:1:num_sources
    vid_info = imaqhwinfo('winvideo',i);
    lst_str{i} = vid_info.DeviceName;
end

if isempty(lst_str)
    errordlg('There is no camera. Please connect a camera and try again.');
    close(hFig);
end

ok = 0;

%Which camera do you want to use?
while ok == 0
    [source_num, ok] = listdlg('ListString',lst_str,'SelectionMode','single','Name',...
        'Camera Selection','PromptString','Which camera would you like to use?',...
        'ListSize', [300 100]);
    
    if ok == 0
        uiwait(errordlg('You must choose a camera!','Error!','modal'));
    end
end

vid_info = imaqhwinfo('winvideo',source_num);

%Now pick a resolution
num_formats = length(vid_info.SupportedFormats);

%Comment this block to diagnose resolution issues
ok = 0;

for i = 1:1:num_formats
   if strcmp(vid_info.SupportedFormats{i}, 'RGB24_640x480')
       vid_format = vid_info.SupportedFormats{i};
       ok = 1;
       break;
   end
    
    if strcmp(vid_info.SupportedFormats{i}, 'YUY2_640x480')
        vid_format = vid_info.SupportedFormats{i};
        uiwait(errordlg('USB Camera driver not installed. Will try to run anyhow.','Warning!','modal'));
        ok = 1;
        break;
    end
end

if ok == 0
    error('Not a supported camera!');
end
%End of block

%Uncommment this block to diagnose resolution issues
% lst_str_f = cell(1,num_formats);
% for i = 1:1:num_formats
%    lst_str_f{i} = vid_info.SupportedFormats{i};
% end
% ok = 0;
% 
% while ok == 0
%    [vid_format_index, ok] = listdlg('ListString',lst_str_f,'SelectionMode','single','Name',...
%        'Resolution Selection','PromptString','Choose 640x480 for best results',...
%        'ListSize', [300 100]);
%     
%    if ok == 0
%        uiwait(errordlg('You must choose a resolution!','Error!','modal'));
%    end
% end
% 
% vid_format = vid_info.SupportedFormats{vid_format_index};
%End of block

%Setup video camera object
vid=videoinput('winvideo',source_num, vid_format);

vid.LoggingMode = 'disk';
triggerconfig(vid, 'immediate');

%Setup the preview pane in the main window
vidRes=get(vid,'VideoResolution');

hImage=imshow(zeros(fliplr(vidRes)));


axis image;

%Start the video preview in the main window
preview(vid, hImage);

%These are all global variables
mouse_id=1;
data_flag=false;


trial_time = 30;
delay_time=trial_time;

%Where the mouse used to be
prev_position = 0;

%Where the mouse is
pos = 0;

%Structure to store how many times the mouse interacts in each zone
%UL = upper left, CT = center, etc....
mouseEvents.ul = 0;
mouseEvents.ur = 0;
mouseEvents.ll = 0;
mouseEvents.lr = 0;
mouseEvents.ct = 0;

%Structure to store how much time mouse spends in each zone
mouseTime.ul = 0;
mouseTime.ur = 0;
mouseTime.ll = 0;
mouseTime.lr = 0;
mouseTime.ct = 0;

%This is the count-down timer that runs the whole experiment
t=timer('TimerFcn',{@action_timer},'StartFcn',{@start_timer},...
    'StopFcn',{@stop_timer},'StartDelay',delay_time);

%This timer updates the display clocks every 100th of a second
t_disp=timer('TimerFcn',{@update_clock},'Period',0.01,'ExecutionMode','fixedRate');

%This clock is used to update the value that the count-down timer is
%counting down from. It is necessary for when the timer stops when the
%mouse is in the center.
master_timer = 0;

%This clock starts fresh each time the mouse enters a new zone and handles
%logging time for the experiment
mouse_timer = 0;

%This next chunk gets the session name and trial identifier
%There is a lot of code to prevent improper data input
session_name='';

dlgbox = inputdlg({'Enter the session name:'});

if ~isempty(dlgbox)
    session_name=dlgbox{1};
end
    
while strcmp(session_name, '')
    uiwait(errordlg('You must enter a session name','Error!','modal'));
    dlgbox = inputdlg({'Enter the session name:'});

    if ~isempty(dlgbox)
        session_name=dlgbox{1};
    end
end

%Define the avi object as global so we can access it later
global vidlog;

%Start logging data to the text file
fid=fopen(['data_logs/' session_name '_data.txt'],'w+');
fprintf(fid,'\r\nSession: %s\r\n', session_name);
fprintf(fid,'%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\r\n',...
    'Mouse ID','Upper L (Time)','Upper R (Time)','Center (Time)','Lower L (Time)',...
    'Lower R (Time)','Upper L (Visits)','Upper R (Visits)','Center (Visits)',...
    'Lower L (Visits)','Lower R (Visits)');
fclose(fid);

%The following code creates the user interface controls
hPnl = uipanel('Title','Timer Controls','Units','normalized','Position',...
    [0.76 0.175 0.23 .5],'BackgroundColor',get(hFig,'Color'),'Parent',hFig);

hPnl_location = uipanel('Title','Mouse Location & Time (s)','Units','normalized',...
    'Position',[0.76 0.7 0.23 0.25],'BackgroundColor',get(hFig,'Color'),'Parent',hFig);

btn_Record = uicontrol('String','Record','Callback',{@record_button},...
    'Units','normalized','Position',[0.05 0.05 0.9 0.25],...
    'FontWeight','bold','FontSize',20,'KeyPressFcn',{@key_down},'Parent',hPnl);

uicontrol('String','Trial Name:','Style','text','Units','normalized',...
    'Position',[0.05 0.65 0.9 0.075],'BackgroundColor',...
    get(hFig,'Color'),'Parent',hPnl);

hMouseID = uicontrol('Style','edit','Units','normalized','FontSize',12,'Enable','On',...
    'String',num2str(mouse_id),'Position',[0.05 0.525 0.9 0.125],'Parent',hPnl,...
    'Callback',{@change_mouse_id});

uicontrol('Style','text','Units','normalized','String','Session:',...
    'Position',[0.05 0.9 0.9 0.075],'BackgroundColor',...
    get(hFig,'Color'),'Parent',hPnl);

uicontrol('Style','edit','Units','normalized','String',session_name,...
    'Position',[0.05 0.775 0.9 0.125],'FontSize',12,'Enable','off','Parent',hPnl);

uicontrol('Style','text','Units','normalized','String','Trial time (s):',...
    'Position',[0.05 0.375 0.6 0.075],'BackgroundColor',get(hFig,'Color'),...
    'Parent',hPnl);

uicontrol('Style','edit','Units','normalized',...
    'String',num2str(trial_time),'Position',[0.55 0.35 0.25 0.125],...
    'Callback',{@change_trial_time},'Parent',hPnl);

txt_UL = uicontrol('Style','edit','Units','normalized','Enable','inactive',...
    'Position',[0.05 0.7 0.43 0.25],'String','0.00','FontSize',14,'Parent',hPnl_location);

txt_UR = uicontrol('Style','edit','Units','normalized','Enable','inactive',...
    'Position',[0.53 0.7 0.43 0.25],'String','0.00','FontSize',14,'Parent',hPnl_location);

txt_LL = uicontrol('Style','edit','Units','normalized','Enable','inactive',...
    'Position',[0.05 0.1 0.43 0.25],'String','0.00','FontSize',14,'Parent',hPnl_location);

txt_LR = uicontrol('Style','edit','Units','normalized','Enable','inactive',...
    'Position',[0.53 0.1 0.43 0.25],'String','0.00','FontSize',14,'Parent',hPnl_location);

txt_CT = uicontrol('Style','edit','Units','normalized','Enable','inactive',...
    'Position',[0.125 0.4 0.75 0.25],'String','0.00','FontSize',14,'Parent',hPnl_location);

uicontrol('String','View Data','Units','normalized',...
    'Position',[0.79 0.05 0.17 0.1],'Callback',{@data_button},'Parent',hFig);

%End of user interface control block

%This is just because I use these colors a lot
btnColor=get(btn_Record,'BackgroundColor');
txtColor=get(txt_CT,'BackgroundColor');


    function change_trial_time(hObject, ~)
        %This function updates the overall experiment time
        trial_time = str2num(get(hObject,'String'));
        delay_time = trial_time;
        set(t,'StartDelay',delay_time);
    end

    function change_mouse_id(hObject,~)
        %This function updates the mouse id
        mouse_id = str2num(get(hObject,'String'));
    end

    function start_timer(~, ~)
        %This calls everytime the mouse leaves the center
        master_timer = tic;
    end

    function stop_timer(hObject, ~)
        %This function handles stopping the experiment timer when the mouse
        %is in the center box. delay_time is how much time is left on the
        %experiment clock at any given moment.
        if delay_time >= 0
            delay_time = round(100*(delay_time-toc(master_timer)))/100;
        else
            delay_time = trial_time;
        end
        
        if get(hObject,'TasksExecuted')>0
            %reset the experiment because it is finished
            delay_time = trial_time;
        end
        
        %have to call this to actuall set the delay time
        set(t,'StartDelay',delay_time);
        
    end

    function action_timer(~, ~)
        %This calls when the overall timer stops and saves the data
        
        switch pos
            %This grabs wherever the mouse was when the experiment ended
            %and saves that data to memory
            case {1}
                set_mouse_timer(1);
            case {3}
                set_mouse_timer(3);
            case {4}
                set_mouse_timer(4);
            case {6}
                set_mouse_timer(6);
            case {0}
                set_mouse_timer(0);
        end
        save_data();
    end

    function record_button(hObject, ~)
        %This function handles the record/abort button
        if data_flag
            %Abort the data taking
            data_flag=false;
            set(hObject,'BackgroundColor',btnColor,'String','Record');
            delay_time=0;
            stop(t);
            
            switch pos
                %This grabs wherever the mouse was when the experiment ended
                %and saves that data to memory
                case {1}
                    set_mouse_timer(1);
                case {3}
                    set_mouse_timer(3);
                case {4}
                    set_mouse_timer(4);
                case {6}
                    set_mouse_timer(6);
                case {0}
                    set_mouse_timer(0);
            end
            save_data();
           
            
         
            
        else
            %Start the data taking
            data_flag=true;
            set(hMouseID,'Enable','off');
            
            %Start recording video to a log file
            vid.FramesPerTrigger = Inf;
            set(vid.Source,'FrameRate', '15');
            
            vidlog = avifile(['data_logs/' session_name '_' num2str(mouse_id)],...
                'compression', 'divx', 'fps', 15);
           

            vid.DiskLogger = vidlog;
            
            
            start(vid);
            
            set(hObject,'BackgroundColor','red');
            set(hObject,'String','ABORT');
            
            set(txt_CT,'BackgroundColor',[0.59,0.78,0.9]);
            
            %Start the local timer for where the mouse is, but don't start
            %the master countdown timer until the mouse leaves the center.
            mouse_timer = tic;
            start(t_disp);
            prev_position = 0;
            
        end
    end

    function set_mouse_timer(cur_position)
       
        switch prev_position
            case {1}
                mouseTime.ll = mouseTime.ll + toc(mouse_timer);
            case {3}
                mouseTime.lr = mouseTime.lr + toc(mouse_timer);
            case{4}
                mouseTime.ul = mouseTime.ul + toc(mouse_timer);
            case{6}
                mouseTime.ur = mouseTime.ur + toc(mouse_timer);
            case{0}
                mouseTime.ct = mouseTime.ct + toc(mouse_timer);
        end

        mouse_timer = tic;
                
        prev_position = cur_position;
    end

    function key_down(~, eventdata)
        %This handles all the user input for where the mouse is
        %It stops the main timer when the mouse is in the center
        %and starts it for anywhere else. It also records an event for
        %the specific location.
        if data_flag
            switch eventdata.Key
                case {'1','numpad1'}
                    if strcmp(get(t,'Running'),'off')
                        start(t);
                    end
                    set_mouse_timer(1);
                    mouseEvents.ll = mouseEvents.ll + 1;
                    pos=1;
                    set(txt_LL,'BackgroundColor',[0.59,0.78,0.9]);
                    set(txt_UL,'BackgroundColor',txtColor);
                    set(txt_LR,'BackgroundColor',txtColor);
                    set(txt_UR,'BackgroundColor',txtColor);
                    set(txt_CT,'BackgroundColor',txtColor);
                case{'3','numpad3'}
                    if strcmp(get(t,'Running'),'off')
                        start(t);
                    end
                    set_mouse_timer(3);
                    mouseEvents.lr = mouseEvents.lr + 1;
                    pos=3;
                    set(txt_LR,'BackgroundColor',[0.59,0.78,0.9]);
                    set(txt_LL,'BackgroundColor',txtColor);
                    set(txt_UL,'BackgroundColor',txtColor);
                    set(txt_UR,'BackgroundColor',txtColor);
                    set(txt_CT,'BackgroundColor',txtColor);
                case{'4','numpad4'}
                    if strcmp(get(t,'Running'),'off')
                        start(t);
                    end
                    set_mouse_timer(4);
                    mouseEvents.ul = mouseEvents.ul + 1;
                    pos=4;
                    set(txt_UL,'BackgroundColor',[0.59,0.78,0.9]);
                    set(txt_LL,'BackgroundColor',txtColor);
                    set(txt_LR,'BackgroundColor',txtColor);
                    set(txt_UR,'BackgroundColor',txtColor);
                    set(txt_CT,'BackgroundColor',txtColor);
                case{'6','numpad6'}
                    if strcmp(get(t,'Running'),'off')
                        start(t);
                    end
                    set_mouse_timer(6);
                    mouseEvents.ur = mouseEvents.ur + 1;
                    pos=6;
                    set(txt_UR,'BackgroundColor',[0.59,0.78,0.9]);
                    set(txt_LL,'BackgroundColor',txtColor);
                    set(txt_UL,'BackgroundColor',txtColor);
                    set(txt_LR,'BackgroundColor',txtColor);
                    set(txt_CT,'BackgroundColor',txtColor);
                case{'0','numpad0'}
                    stop(t);
                    set_mouse_timer(0);
                    mouseEvents.ct = mouseEvents.ct + 1;
                    pos=0;
                    set(txt_CT,'BackgroundColor',[0.59,0.78,0.9]);
                    set(txt_LL,'BackgroundColor',txtColor);
                    set(txt_UL,'BackgroundColor',txtColor);
                    set(txt_LR,'BackgroundColor',txtColor);
                    set(txt_UR,'BackgroundColor',txtColor);
                otherwise
                    beep;
                    
            end
        end
    end

    function update_clock(~, ~)
        switch pos
            case {0}
                str = sprintf('%5.2f',round(100*(mouseTime.ct + toc(mouse_timer)))/100);
                set(txt_CT,'String',str);
            case {1}
                str = sprintf('%5.2f',round(100*(mouseTime.ll + toc(mouse_timer)))/100);
                set(txt_LL,'String',str);
            case {3}
                str = sprintf('%5.2f',round(100*(mouseTime.lr + toc(mouse_timer)))/100);
                set(txt_LR,'String',str);
            case {4}
                str = sprintf('%5.2f',round(100*(mouseTime.ul + toc(mouse_timer)))/100);
                set(txt_UL,'String',str);
            case {6}
                str = sprintf('%5.2f',round(100*(mouseTime.ur + toc(mouse_timer)))/100);
                set(txt_UR,'String',str);
        end
    end


    function save_data()
        %This saves all the text data, and also wraps up the video file.
        stop(t_disp);
        data_flag=false;
        set(btn_Record,'BackgroundColor',btnColor,'String','Record');
        fid = fopen(['data_logs/' session_name '_data.txt'], 'a');
        fprintf(fid, '%s\t%s\t%d\t%5.3f\t%d\t%5.3f\t%d\t%5.3f\t%d\t%5.3f\t%d\t%5.3f\r\n',...
            datestr(now), get(hMouseID, 'String'),...
            mouseTime.ul, mouseTime.ur, mouseTime.ct,...
            mouseTime.ll, mouseTime.lr, mouseEvents.ul,...
            mouseEvents.ur, mouseEvents.ct, mouseEvents.ll,...
            mouseEvents.lr);
        fclose(fid);
        
        stop(vid);
        
        while (vid.DiskLoggerFrameCount ~= vid.FramesAcquired)
            pause(1);
            round(100*vid.DiskLoggerFrameCount/vid.FramesAcquired)
        end
   
        vidlog = close(vid.DiskLogger);
        
        
        
        mouse_id = mouse_id + 1;
        reset_trial();
        
    end

    function reset_trial()
        %This just sets all the data variable back to zero and resets the
        %experiment
        prev_position = 0;
        pos = 0;

        mouseEvents.ul = 0;
        mouseEvents.ur = 0;
        mouseEvents.ll = 0;
        mouseEvents.lr = 0;
        mouseEvents.ct = 0;

        mouseTime.ul = 0;
        mouseTime.ur = 0;
        mouseTime.ll = 0;
        mouseTime.lr = 0;
        mouseTime.ct = 0;
        
        set(txt_CT,'String','0.00');
        set(txt_UR,'String','0.00');
        set(txt_UL,'String','0.00');
        set(txt_LR,'String','0.00');
        set(txt_LL,'String','0.00');
        
        set(txt_LL,'BackgroundColor',txtColor);
        set(txt_UL,'BackgroundColor',txtColor);
        set(txt_LR,'BackgroundColor',txtColor);
        set(txt_UR,'BackgroundColor',txtColor);
        set(txt_CT,'BackgroundColor',txtColor);
        
        set(hMouseID, 'String', num2str(mouse_id), 'Enable', 'On');
    end

    function data_button(~, ~)
        %Open the datafile in your favorite text editor
        winopen(['data_logs/' session_name '_data.txt']);
    end

    function delete_figure(~, ~)
        %Clean up the memory when the program closes
        delete(t);
        delete(t_disp);
        delete(vid);
        clear vid;
        clear all;
    end

end
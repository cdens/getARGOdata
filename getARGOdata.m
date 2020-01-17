function getARGOdata(outputfilename,daterange,varargin)

% getARGOdata(outputfilename,daterange)
% Author: Casey R. Densmore
%
% This function downloads ARGO profiles from the ARGO website 
%   https://data.nodc.noaa.gov/argo/gadr/inv/basins/ for all dates within
%   daterange and saves them to a .mat file specified by outputfilename.
%
% daterange should be a 2-value array with dates in datenum format 
%   e.g. [datenum(2017,12,31), datenum(2018,2,3,9,18,30)]
% 
% outputfilename should be either a char or string array, e.g. 
%   'output.mat' or "output.mat"
%
% Profiles are saved in a structure 'argoprofs', with the fields temp,
%   depth, date, lat, and lon
%
% Optional input arguments:
%   o monthrange: a 2-value array that specifies limiting months for
%       profiles (e.g. monthrange=[7,8] specifies profiles collected between
%       July and August only)
%   o latrange, lonrange: 2-value arrays that specify latitudes and
%       longitudes to constrain reported profiles (e.g. lonrange = [-30,12]
%       specifies profiles between 30W and 12E). lonrange inputs should be 
%       between -180 and 180, with degE > 0, and latrange inputs should be
%       between -90 and 90, with degN > 0
%   o mindepth: a single value specifying minimum depth for profiles to
%       save, in meters (e.g. mindepth = 200)
%   o basins: a cell array listing the basins (atlantic, pacific, or
%       indian) to search for valid profiles (e.g. basins = {'atlantic','indian'}
%       To specify a single basin, place the name inside cell operators,
%       e.g. basins = {'atlantic'}
%


%% parsing function inputs

if (~ischar(outputfilename) && ~isstring(outputfilename))
    error('Invalid argument passed for outputfilename')
elseif length(daterange) ~= 2 || ~isnumeric(daterange)
    error('Invalid argument passed for daterange')
end

%setting yearrange from required "daterange"
[yearrange(1),~] = datevec(daterange(1));
[yearrange(2),~] = datevec(daterange(2));

%set optional values to empty
monthrange = [];
lonrange = [];
latrange = [];
mindepth = [];
basins = {};

%parsing optional inputs
if nargin >= 4 %2 mandatory + at least 2 (key+value) optional inputs
    for n = 2:2:nargin-2
        key = varargin{n-1};
        value = varargin{n};
        
        switch(lower(key))
            case 'monthrange'
                if length(value) ~= 2 || ~isnumeric(value)
                    warning('Invalid argument passed for monthrange, using default value')
                else
                    monthrange = value;
                end
                
            case 'lonrange'
                if length(value) ~= 2 || ~isnumeric(value)
                    warning('Invalid argument passed for lonrange, using default value')
                else
                    lonrange = value;
                end
                
            case 'latrange'
                if length(value) ~= 2 || ~isnumeric(value)
                    warning('Invalid argument passed for latrange, using default value')
                else
                    latrange = value;
                end
                
            case 'mindepth'
                if length(value) ~= 1 || ~isnumeric(value)
                    warning('Invalid argument passed for mindepth, using default value')
                else
                    mindepth = value;
                end
                
            case 'basins'
                if ~iscell(value)
                    warning('Invalid argument passed for basins, using default value')
                else
                    basins = value;
                end
        end
    end
end

%setting defaults for all unfilled values
if isempty(monthrange)
    monthrange = [1,12];
end
if isempty(lonrange)
    lonrange = [-180,180];
end
if isempty(latrange)
    latrange = [-90,90];
end
if isempty(mindepth)
    mindepth = -10; %ensure no profiles will be missed using negative depth
end
if isempty(basins)
    basins = {'atlantic','pacific','indian'};
end


%% Searching through all ARGO indices over specified year range to find valid profiles
s = 0; %counter for profiles to be saved

fprintf('Checking ARGO Index Data\n')
for y = yearrange(1):yearrange(2)
    for m = monthrange(1):monthrange(2) %only checking June through October data
        for b = 1:length(basins)
            
            %basic variables to download data
            basin = lower(basins{b}); %lowercase to match site setup
            yyyy = num2str(y);
            mm = num2str(m);
            if length(mm) == 1
                mm = ['0',mm];  %#ok<AGROW>
            end
            
            disp(['Checking: year=',yyyy,' month=',mm,' basin=',basin]);
            
            %downloading data, reading to matlab
            indexurl = ['https://data.nodc.noaa.gov/argo/gadr/inv/basins/',basin,'/',yyyy,'/',...
                basin(1:2),yyyy,mm,'_argoinv.txt'];
            [~,status] = urlread(indexurl); %#ok<URLRD>
            if status == 1 %only if the index exists
                websave('temp1.txt',indexurl); %saves the index data to a file
                
                %reading the index data, checking if it is within range of
                %a storm
                fid = fopen('temp1.txt');
                fgetl(fid); %reading in the header
                while ~feof(fid)
                    readin = fgetl(fid);
                    readsplit = strsplit(readin,',');
                    
                    if strcmp(readsplit{1},'0') == 0
                        
                        %getting current float data
                        filepath = readsplit{3};
                        dateminstr = readsplit{4};
                        datemaxstr = readsplit{5};
                        latmin = str2num(readsplit{6});
                        latmax = str2num(readsplit{7});
                        lonmin = str2num(readsplit{8});
                        lonmax = str2num(readsplit{9});
                        depthmax = str2num(readsplit{11});
                        
                        %getting datenums from the date strings
                        datemin = datenum(str2num(dateminstr(1:4)),str2num(dateminstr(6:7)),...
                            str2num(dateminstr(9:10)),str2num(dateminstr(12:13)),...
                            str2num(dateminstr(15:16)),str2num(dateminstr(18:19))); %#ok<*ST2NM>
                        
                        datemax = datenum(str2num(datemaxstr(1:4)),str2num(datemaxstr(6:7)),...
                            str2num(datemaxstr(9:10)),str2num(datemaxstr(12:13)),...
                            str2num(datemaxstr(15:16)),str2num(datemaxstr(18:19)));
                        
                        %calling function to check if profile is within range
                        whatdo = false;
                        if depthmax >= mindepth
                            whatdo = checkdata(datemin,datemax,latmin,latmax,lonmin,lonmax,daterange,latrange,lonrange);
                        end
                        
                        %if function says it should be downloaded- saves
                        %filepath to download in next section
                        if whatdo
                            s = s + 1;
                            filestodownload{s} = filepath; %#ok<AGROW,*SAGROW>
                        end
                        
                    end
                end
                
                %closing and deleting the index file
                fclose(fid); 
                
            else %prints to the command line if the queried ARGO index doesn't exist
                fprintf(2,['Unable to access metadata for: year=',yyyy,' month=',mm,' basin=',basin,'\n'])
            end
        end
    end
end
fprintf('Index Checks Complete: Downloading Relevant Data')



%% Downloading the files that fell within the criteria
m = 0;
for s = 1:length(filestodownload)
    filecur = ['https://data.nodc.noaa.gov/argo/gadr/',filestodownload{s}];
    
    try
        disp(['Downloading ',filecur])
        websave('out.nc',filecur);
        
        proftemp = ncread('out.nc','temp');
        profdepth = ncread('out.nc','pres');
        proflat = ncread('out.nc','latitude');
        proflon = ncread('out.nc','longitude');
        profdate = ncread('out.nc','juld') + datenum(1950,1,1,0,0,0);
        
        [~,ind] = unique(profdate);
        
        for i = ind %for every unique profile, saving the data
            m = m + 1;
            argoprofs(m).temp = proftemp(:,i); %#ok<AGROW,*SAGROW>
            argoprofs(m).depth = profdepth(:,i); %#ok<AGROW,*SAGROW>
            argoprofs(m).date = profdate(i); %#ok<AGROW,*SAGROW>
            argoprofs(m).lat = proflat(i); %#ok<AGROW,*SAGROW>
            argoprofs(m).lon = proflon(i); %#ok<AGROW,*SAGROW>
        end
        
    catch
        fprintf(['File Not Found: ',filecur,'\n'])
    end
    
end
disp('Data download completed- saving profiles')

%saving and cleaning up
clearvars -except argoprofs
save(outputfilename)
delete temp1.txt out.nc
disp('Finished saving profiles- function completed!')


end %END OF FUNCTION



%% function to check if conditions are met for specific profile
function whatdo = checkdata(datemin,datemax,latmin,latmax,lonmin,lonmax,daterange,latrange,lonrange)

%datenum(year,month,day,hour,minute,second), lat in degN, lon in degE
if datemin >= daterange(1) && datemax <= daterange(2) ...
        && latmin >= latrange(1) && latmax <= latrange(2) ...
        && lonmin >= lonrange(1) && lonmax < lonrange(2)
    whatdo = true;
else %if no conditions are met
    whatdo = false;
end

end
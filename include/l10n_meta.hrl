
-export([get_path/2, get_file/2, get_type/0, get_name/1, source_files/0]).
-export([start_link/0]).
-export([format/2, string/1]).
-export([generate/1]).

% Protected
-export([get_table/1, is_available/1]).

-ifndef(L10N_SERVER).
-define(L10N_SERVER, ?MODULE).
-endif.

-ifndef(L10N_TABLE).
-define(L10N_TABLE, ?MODULE).
-endif.

-ifndef(L10N_TYPE).
-define(L10N_TYPE, 'string').
-endif.

-ifdef(L10N_APPLICATION).
-define(L10N_PATH(T, L),
	begin	
		code:priv_dir(?L10N_APPLICATION) ++ "/translates/" 
			++ ?MODULE_STRING ++ "/"
			++ atom_to_list(L) ++ "." ++ atom_to_list(T)
	end).

-define(L10N_LOCALES,
	begin	
		DirName = code:priv_dir(?L10N_APPLICATION) ++ "/translates/" 
			++ ?MODULE_STRING,
		Files = filelib:wildcard(DirName ++ "/*.po"),
    	[ list_to_atom(filename:basename(X, ".po")) || X <- Files ]
	end).

-define(L10N_SOURCE,
	begin
    	DirName = code:lib_dir(?L10N_APPLICATION, src),
    	filelib:wildcard(DirName ++ "/*.erl")
	end).
-endif.


-type l10n_file_type() :: 'po' | 'pot'.
-type l10n_locale() :: atom().

-spec get_path(l10n_file_type(), l10n_locale()) -> string().
get_path(Type, Locale) ->
	?L10N_PATH(Type, Locale).

get_name('domain') -> ?MODULE;
get_name('table')  -> ?L10N_TABLE;
get_name('server') -> ?L10N_SERVER.

source_files() ->
	?L10N_SOURCE.

%% format | string
get_type() -> ?L10N_TYPE.


available_locales() ->
	?L10N_LOCALES.

is_available(L) ->
	F = get_path('po', L),
	filelib:is_file(F).

%% @doc Start the store server.
start_link() ->
	l10n_spawn_server:start_link(?MODULE).

format(Id, Params) ->
	?L10N_TYPE = 'format',
	H = l10n_utils:hash(Id),
	format(H, Id, Params).

format(H, Id, Params) ->
	Fmt = case search(H, 5) of
		false -> 
			X = l10n_utils:format(Id), 
			insert(H, X),
			X;
		X -> X
		end,
	i18n_message:format(Fmt, Params).
	

string(Id) ->
	?L10N_TYPE = 'string',
	H = l10n_utils:hash(Id),
	string(H, Id).

%% @doc Try to search a string in the data store.
%%		If the string is not found, add it.
string(H, Id) ->
	?L10N_TYPE = 'string',
	H = l10n_utils:hash(Id),
	case search(H, 5) of
	[] ->
		X = l10n_utils:string(Id), 
		insert(H, X),
		X;
	[{_,X}] -> X
	end.

%% @doc Retrieve Hash(Key) from the data store.
search(H, Count) 
	when Count > 0 ->
	try
		T = get(?L10N_TABLE),
		ets:lookup(T, H)
	catch error:_ ->
		L = l10n_locale:get_locale(),
		get_table(L),
		search(H, Count - 1)
	end.

%% @doc Put the locale table id of the data store to the process dictionary.
%%		Return table id.		
get_table(L) ->
	P = l10n_spawn_server:find_store(?MODULE, L),
	T = l10n_store_server:get_table(P),
	put(?L10N_TABLE, T),
	% When user calls l10n_locale:set_locale(...),
	% this tid will be erased.
	l10n_locale:add_domain(?MODULE),
	T.


%% @doc Send {Key, Value} to the store server.
insert(Key, Value) ->
	L = l10n_locale:get_locale(),
	P = l10n_spawn_server:find_store(?MODULE, L),
	l10n_store_server:update_value(P, Key, Value).
	
%% @doc Writes parsed data to files.
generate('pot') ->
	Values = l10n_parser:parse(?MODULE),
	IOList = l10n_export:to_pot(Values),
	FileName = get_path('pot', 'root'),
	ok = filelib:ensure_dir(FileName),
	l10n_utils:file_write(FileName, IOList),
	ok;
	
generate('po') ->
	SRC = l10n_parser:parse(?MODULE),
	Locales = available_locales(),
	F = fun(L) ->
		PO = get_file('po', L),
		IOList = l10n_export:to_po(PO, SRC),
		FileName = get_path('po', L),
		l10n_utils:file_write(FileName, IOList)
		end,
	lists:map(F, Locales),
	ok.

%% @doc Extract PO data from file.
get_file('po', Locale) ->
	FileName = get_path('po', Locale),
	l10n_import:from_po(FileName).
	

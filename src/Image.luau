--!strict

local ContentProvider = game:GetService("ContentProvider")

export type Target = ImageLabel | ImageButton
export type State = {
	status: "idle" | "loading" | "loaded" | "error",
	generation: number,
	sourceType: "none" | "uri" | "object",
	uri: string?,
	object: Object?,
	error: string?,
	fetchStatus: Enum.AssetFetchStatus?,
	fetchObservationError: string?,
}
export type Options = { onState: ((State) -> ())? }
export type Binding = {
	getState: () -> State?,
	-- Application failures are accepted only for this observed source generation.
	setError: (number, string?) -> boolean,
	destroy: () -> (),
}

local Image = {}

local function same(a: State?, b: State): boolean
	return a ~= nil
		and a.status == b.status
		and a.generation == b.generation
		and a.sourceType == b.sourceType
		and a.uri == b.uri
		and a.object == b.object
		and a.error == b.error
		and a.fetchStatus == b.fetchStatus
		and a.fetchObservationError == b.fetchObservationError
end

function Image.bind(image: Target, options: Options?, onRelease: () -> ()): Binding
	local defaults: Options = options or {}
	local settings = table.clone(defaults)
	local connections: { RBXScriptConnection } = {}
	local destroyed, pending = false, false
	local target: Target? = image
	local releaseCallback: (() -> ())? = onRelease
	local state: State? = nil
	local announced: State? = nil
	local generation = 0
	local applicationError: string? = nil
	local fetchConnection: RBXScriptConnection? = nil
	local fetchUri: string? = nil
	local fetchObservationError: string? = nil
	local refresh: () -> ()
	local hasContent = pcall(function()
		return image.ImageContent
	end)
	local function release()
		if destroyed then
			return
		end
		destroyed = true
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if fetchConnection then
			fetchConnection:Disconnect()
			fetchConnection = nil
		end
		fetchUri, fetchObservationError = nil, nil
		state, announced, applicationError = nil, nil, nil
		target = nil
		settings.onState = nil
		local callback = releaseCallback
		releaseCallback = nil
		if callback then
			callback()
		end
	end
	local function observeFetch(uri: string?)
		if uri == fetchUri then
			return
		end
		if fetchConnection then
			fetchConnection:Disconnect()
			fetchConnection = nil
		end
		fetchUri, fetchObservationError = uri, nil
		if not uri then
			return
		end
		local observedGeneration = generation
		local ok, connection = pcall(function()
			return ContentProvider:GetAssetFetchStatusChangedSignal(uri):Connect(function()
				if not destroyed and generation == observedGeneration and fetchUri == uri then
					refresh()
				end
			end)
		end)
		if ok then
			fetchConnection = connection
		else
			fetchObservationError = `native-asset-fetch-signal-unavailable:{tostring(connection)}`
		end
	end
	local function notify()
		if pending or not settings.onState then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			local snapshot = state
			if destroyed or not snapshot or same(announced, snapshot) then
				return
			end
			announced = table.clone(snapshot)
			if settings.onState then
				settings.onState(table.clone(snapshot))
			end
		end)
	end
	local function read(): State
		local current = target
		assert(current ~= nil, "Image observer has been destroyed")
		local sourceType: "none" | "uri" | "object" = "none"
		local uri: string? = nil
		local object: Object? = nil
		if hasContent then
			local content = current.ImageContent
			local kind = content.SourceType.Name
			if kind == "Uri" then
				sourceType, uri = "uri", content.Uri
				assert(uri ~= nil, "Native image URI is unavailable")
			elseif kind == "Object" then
				sourceType, object = "object", content.Object
				assert(object ~= nil, "Native image object is unavailable")
			elseif kind ~= "None" then
				error(`Native image source observer requires a provider for ContentSourceType.{kind}`, 0)
			end
		else
			local legacy = current.Image
			if legacy ~= "" then
				sourceType, uri = "uri", legacy
			end
		end
		local previous = state
		if not previous or previous.sourceType ~= sourceType or previous.uri ~= uri or previous.object ~= object then
			generation += 1
			applicationError = nil
		end
		observeFetch(uri)
		local fetchStatus: Enum.AssetFetchStatus? = nil
		local observationError = fetchObservationError
		if uri then
			local ok, result = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, uri)
			if ok then
				fetchStatus = result
			else
				observationError = observationError or `native-asset-fetch-status-unavailable:{tostring(result)}`
			end
		end
		local loaded = current.IsLoaded
		local reason = applicationError
		if reason == nil and not loaded then
			if fetchStatus == Enum.AssetFetchStatus.Failure then
				reason = "native-asset-fetch-failure"
			elseif fetchStatus == Enum.AssetFetchStatus.TimedOut then
				reason = "native-asset-fetch-timeout"
			end
		end
		return {
			status = if reason ~= nil
				then "error"
				elseif sourceType == "none" then "idle"
				elseif loaded then "loaded"
				else "loading",
			generation = generation,
			sourceType = sourceType,
			uri = uri,
			object = object,
			error = reason,
			fetchStatus = fetchStatus,
			fetchObservationError = observationError,
		}
	end
	refresh = function()
		if destroyed then
			return
		end
		local ok, snapshot = pcall(read)
		if not ok then
			local clean, cleanupFailure = pcall(release)
			if not clean then
				error(`Image observation: {tostring(snapshot)}; cleanup: {tostring(cleanupFailure)}`, 0)
			end
			error(snapshot, 0)
		end
		if not destroyed and not same(state, snapshot) then
			state = snapshot
			notify()
		end
	end
	local binding: Binding = {
		getState = function()
			refresh()
			return if state then table.clone(state) else nil
		end,
		setError = function(observedGeneration, reason)
			refresh()
			if destroyed or not state or observedGeneration ~= state.generation then
				return false
			end
			applicationError = reason
			refresh()
			return not destroyed
		end,
		destroy = release,
	}
	local ok, failure = pcall(function()
		table.insert(connections, image.Destroying:Connect(release))
		table.insert(connections, image:GetPropertyChangedSignal("Image"):Connect(refresh))
		if hasContent then
			table.insert(connections, image:GetPropertyChangedSignal("ImageContent"):Connect(refresh))
		end
		table.insert(connections, image:GetPropertyChangedSignal("IsLoaded"):Connect(refresh))
		refresh()
	end)
	if not ok then
		local clean, cleanupFailure = pcall(release)
		if not clean then
			error(`Image binding: {tostring(failure)}; cleanup: {tostring(cleanupFailure)}`, 0)
		end
		error(failure, 0)
	end
	return binding
end

return Image

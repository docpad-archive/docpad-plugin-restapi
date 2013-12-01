# Export Plugin
module.exports = (BasePlugin) ->
	# Define Plugin
	class RestAPI extends BasePlugin

		# Plugin name
		name: 'restapi'
		config:
			channel: '/restapi'
			maxFilenameLen: 40
			injectHelper: null

		# Server Extend Event
		# Add all of our REST Routes
		serverExtend: (opts) ->
			plugin = @
			docpad = @docpad
			{server} = opts
			{channel} = @getConfig()

			# Send Reslut
			sendSuccessData = (res,data,message) ->
				res.send(
					success: true
					message: message or "Action completed successfully"
					data: data
				)

			# Send Success Message
			sendSuccessMessage = (res,message) ->
				res.send(
					success: true
					message: message
				)

			# Send Error
			sendError = (res,err) ->
				res.send(
					success: false
					message: err.message+': \n'+err.stack.toString()
				)

			# Prepare file data for sending
			prepareFile = (file, additionalFields) ->
				# Prepare
				result = {}
				fields = ['filename', 'relativePath', 'url', 'urls', 'contentType', 'encoding', 'source', 'content', 'contentRendered', 'date']
				additionalFields ?= []
				additionalFields = String(additionalFields).split(/[,\s]+/)  unless Array.isArray(additionalFields)

				# Give the user all fields if they want that
				if additionalFields.length is 1 and additionalFields[0] is 'all'
					result = file.toJSON()

				# Otherwise give the user specific fields
				else
					result.meta = file.getMeta().toJSON()
					for field in fields.concat(additionalFields)
						result[field] = file.get(field)

				# Get it working
				if result.meta.layout
					result.meta.layout = file.get('layoutRelativePath')

				# return the result
				return result

			# Prepare collection data for sending
			prepareCollection = (collection, additionalFields) ->
				result = []
				collection.each (file) ->
					result.push prepareFile(file, additionalFields)
				return result

			# Prepare collections
			prepareCollections = ->
				result = []

				addCollection = (collection) ->
					relativePaths = []
					#ids = []

					collection.each (model) ->
						relativePath = model.get('relativePath')
						relativePaths.push(relativePath)  if relativePath
						#ids.push(model.id)  if model.id

					result.push
						name: collection.options.name
						length: collection.length
						relativePaths: relativePaths
						#ids: ids

				addCollection(docpad.getDatabase())
				for own key,value of docpad.getCollections()
					addCollection(value)

				return result

			# Get Unique Filename
			# TODO: How should this work with files name jquery.min.js ?
			getUniqueRelativePath = (relativePath) ->
				# Prepare
				result = relativePath
				extensions = relativePath.replace(/^.+?\./, '')

				# Iterate while found
				while (file = docpad.getDatabase().where({relativeBase: result.replace(/\..*$/, '')})[0])
					# test.txt
					# > test-2.html
					# > test-3.html.md
					basename = file.get('basename')
					relativeDirPath = file.get('relativeDirPath')
					parts = /^(.+?)-([0-9]+)$/.exec(basename)
					if parts
						basename = parts[1]+'-'+(parseInt(parts[2], 10)+1)
					else
						basename += '-2'
					result = relativeDirPath+'/'+basename
					result += '.'+extensions  if extensions

				# Return
				return result

			# Get files from request
			# next(err, files, file)
			# return files/files
			getFilesFromRequest = (req,next) ->
				# Prepare
				files = null
				queryOpts = null
				sortOpts = null
				pageOpts = null

				# Extract
				relativePath = req.params[0] or null
				collectionName = req.params.collectionName
				mime = req.query.mime or null
				extension = req.query.extension or null
				page = req.query.page or null
				limit = req.query.limit ? null
				offset = req.query.offset ? null
				filter = req.query.filter

				# Check
				collection = docpad.getCollection(collectionName)
				unless collection
					err = new Error("Couldn't find the collection: #{collectionName}")
					return next(err); err

				# Add paging
				if page? or limit? or offset?
					pageOpts ?= {}
					pageOpts.page = parseInt(page, 10)  if page?
					pageOpts.limit = parseInt(limit, 10)  if limit?
					pageOpts.offset = parseInt(offset, 10)  if offset?

				# Add filter to query
				if filter
					try
						queryOpts = JSON.parse(filter)
					catch err
						err = new Error("Failed to parse your custom filter: #{JSON.stringify(filter)}")
						return next(err); err

				# Add the relative path to the query
				if relativePath
					queryOpts ?= {}
					queryOpts.$or =
						relativePath: relativePath
						relativeDirPath: relativePath.replace(/[\/\\]+$/, '')

				# Add extension to query
				if extension
					queryOpts ?= {}
					queryOpts.extensions = $has: extension

				# Add mime to query
				if mime
					queryOpts ?= {}
					queryOpts.outContentType = $like: mime

				# Perform filters
				result =
					if queryOpts or sortOpts or pageOpts
						collection.findAll(queryOpts, sortOpts, pageOpts)
					else
						collection

				# Return
				return next(null, result); result

			# Delete files from request
			# next(err, files)
			# return err/files
			deleteFilesFromRequest = (req,next) ->
				# Import
				{TaskGroup} = require('taskgroup')

				# Fetch
				return getFilesFromRequest req, (err, files) ->
					# Check
					return next(err)  if err
					return next(null, files)  if files.length is 0

					# Delete and remove files from database in parallel
					# Create task group
					tasks = new TaskGroup().setConfig(concurrency:0).once 'complete', (err) ->
						# Check
						return next(err)  if err

						# Generate
						docpad.action 'generate', {reset:false}, (err) ->
							return next(err, files)

					# Add tasks
					files.each (file) ->  tasks.addTask (complete) ->
						file.deleteSource (err) ->
							return complete(err)  if err
							docpad.getDatabase().remove(file)
							return complete()

					# Run
					tasks.run()

			# Create a new file from request
			# next(err)
			# return err/file
			createFileFromRequest = (req,next) ->
				# Prepare
				docpadConfig = docpad.getConfig()
				config = plugin.getConfig()

				# Extract
				collectionName = req.params.collectionName
				relativePath = req.params[0]

				# Check
				collection = docpad.getCollection(collectionName)
				unless collection
					err = new Error("Couldn't find the collection: #{collectionName}")
					return next(err); err

				# Check
				unless relativePath
					err = new Error("No relativePath to place the file specified")
					return next(err); err

				# Ensure unique filename
				relativePath = getUniqueRelativePath(relativePath)
				fullDirPath = docpadConfig[collectionName+'Paths']?[0] or null
				fullPath = "#{fullDirPath}/#{relativePath}"  if fullDirPath

				# Set up our meta attributes
				fileMetaAttributes = {}
				for own key,value of req.body
					fileMetaAttributes[key] = value  unless key in ['content']

				# Set up our attributes
				fileAttributes =
					data: req.body.content or ''
					relativePath: relativePath
					fullPath: fullPath
					meta: fileMetaAttributes

				# Create the file, inject helper and add the file to the database
				file = docpad.createModel(fileAttributes)

				# Inject helper
				config.injectHelper?.call(plugin, file)

				# add it to the database
				docpad.getDatabase().add(file)

				# Write source
				file.writeSource {cleanAttributes:true}, (err) ->
					# Check
					return next(err, file)  if err

					# Generate
					docpad.action 'generate', {reset:false}, (err) ->
						return next(err, file)

				# Return the created file
				return file

			# Update file from request
			# next(err)
			# return err/file
			updateFileFromRequest = (req,next) ->
				# Extract
				collectionName = req.params.collectionName
				relativePath = req.params[0]

				# Check
				collection = docpad.getCollection(collectionName)
				unless collection
					err = new Error("Couldn't find the collection: #{collectionName}")
					return next(err); err

				# Check
				unless relativePath
					err = new Error("No relativePath to find the file specified")
					return next(err); err

				# Find
				file = collection.where({relativePath})[0]
				unless file
					err = new Error("Couldn't find the file at the relative path: #{relativePath}")
					return next(err); err

				# Set up our meta attributes
				setMeta = false
				fileMetaAttributes = {}
				for own key,value of req.body
					setMeta = true
					fileMetaAttributes[key] = value  unless key in ['content']
				file.setMeta(fileMetaAttributes)  if setMeta

				# Set up our write source options
				writeSourceOptions = {}
				writeSourceOptions.cleanAttributes = true
				writeSourceOptions.content = req.body.content  if req.body.content?

				# Write source
				file.writeSource writeSourceOptions, (err) ->
					# Check
					return next(err, file)  if err

					# Generare
					docpad.action 'generate', {reset:false}, (err) ->
						# ^ if we don't do reset, then the document we create above is not the one picked up by parsing
						# we need to fix this
						return next(err, file)

				# Return the created file
				return file

			###
			# Upload a file
			server.post "#{channel}/upload", (req, res) ->
				# Requires
				safefs = require('safefs')

				successful = []
				failed = []
				currentlyUploading = []
				count = 0

				uploadFile = (file) ->
					path = file.path
					origName = name = docpadConfig.filesPaths[0] + '/' + file.name
					renameCounter = 0

					# save an uploaded file
					save = ->  safefs.rename path, name, (err) ->
						unless err
							if renameCounter
								successful.push
									origName: file.name
									newName: name.replace(docpadConfig.filesPaths[0] + '/', '')
							else
								successful.push
									name: file.name
						else
							console.log err
							failed.push
								file: file.name
								error: err
						unless --count
							if successful.length + failed.length is 1
								return res.send(if successful.length then (success: successful) else (success: false, error: failed))
							res.send
								success: successful
								error: failed

					# Save an uploaded file with a unique name
					saveUnique = (exists) ->
						# Name is not unique, try again
						if (exists or currentlyUploading.indexOf(name) > -1)
							name = origName.replace(/(.*?)(\..*)/, '$1-' + (++renameCounter) + '$2')
							return safefs.exists(name, saveUnique)
						# Unique name found, let's save it
						currentlyUploading.push(name);
						save()

					# Save each uploaded file
					safefs.exists(name, saveUnique)

				# Iterate through each uploaded file
				for own key of req.files
					if req.files[key].name
						count++
						uploadFile req.files[key]

				# If no work to be done, let the user know
				unless count
					res.send(error: 'No Files specified')
			###

			# CORS
			server.all "#{channel}/*", (req,res,next) ->
				res.header('Access-Control-Allow-Origin', '*');
				res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE');
				res.header('Access-Control-Allow-Headers', 'Content-Type,X-Requested-With');
				return next()

			# Fetch the templateData
			server.all "#{channel}/template-data/", (req,res) ->
				result = docpad.getTemplateData()
				return sendSuccessData(res, result, "Listing of template data completed successfully")

			# Fetch the files
			server.all "#{channel}/files/", (req,res) ->
				return res.redirect(301, "#{channel}/collection/database/")

			# Fetch the files
			server.all "#{channel}/file/*", (req,res) ->
				return res.redirect(301, "#{channel}/collection/database/#{req.params[0]}")

			# Fetch the collections
			server.all "#{channel}/collections/", (req,res) ->
				result = prepareCollections()
				return sendSuccessData(res, result, "Listing of collections completed successfully")

			# CRUD on collections and files
			server.all "#{channel}/collection/:collectionName/*", (req,res) ->
				# Prepare
				method = req.method.toLowerCase()

				# Get
				if method is 'get'
					# Fetch
					collectionName = req.params.collectionName
					relativePath = req.params[0]
					additionalFields = req.query.additionalFields or req.query.additionalfields

					# List
					getFilesFromRequest req, (err, files) ->
						# Check
						return sendError(res, err)  if err

						# Send
						return sendSuccessData(res, prepareCollection(files, additionalFields), "Listing of #{collectionName} at #{relativePath} completed successfully")

				# Delete
				else if method is 'delete'

					# List
					deleteFilesFromRequest req, (err, files) ->
						# Check
						return sendError(res, err)  if err

						# Send
						return sendSuccessData(res, prepareCollection(files, additionalFields), "Delete completed successfully")

				# Put
				else if method is 'put'
					# Fetch
					additionalFields = req.query.additionalFields or req.query.additionalfields

					# Create
					createFileFromRequest req, (err,file) ->
						# Check
						return sendError(res, err)  if err

						# Send
						return sendSuccessData(res, prepareFile(file, additionalFields), "Creation completed successfully")

				# Post
				else if method is 'post'
					# Fetch
					additionalFields = req.query.additionalFields or req.query.additionalfields

					# Update
					updateFileFromRequest req, (err,file) ->
						# Check
						return sendError(res, err)  if err

						# Send
						return sendSuccessData(res, prepareFile(file, additionalFields), "Update completed successfully")

				# Unknown
				else
					err = Error("Unknown method: #{method}")
					sendError(res, err)

				# Done
				return

			# Chain
			@
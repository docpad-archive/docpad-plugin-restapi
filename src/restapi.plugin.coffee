# Export Plugin
module.exports = (BasePlugin) ->
	# Requires
	safefs = require('safefs')

	# Define Plugin
	class RestAPI extends BasePlugin

		# Plugin name
		name: 'restapi'
		config:
			channel: '/restapi'
			maxFilenameLen: 40

		# Server Extend Event
		# Add all of our REST Routes
		serverExtend: (opts) ->
			docpad = @docpad
			config = @getConfig()
			database = docpad.getDatabase()
			docpadConfig = docpad.getConfig()
			{server} = server
			fsPath = docpadConfig.documentsPaths[0] + '/'

			# Write, Update, and Delete Helper Functions
			findUniqueFilename = (filename) ->
				count = 1
				origFilename = filename
				while(docpad.getFile(relativePath: filename))
					filename = origFilename.replace(/([^ .]*)(\.)?/, '$1' + '-' + (++count) + '$2')
				filename

			fixFilePath = (str) ->
				str?.trim().split(' ').join('-').substring(0, config.maxFilenameLen).toLowerCase()

			getFilenameFromReq = (req) ->
				fixFilePath(req.params[0] or req.body.filename or req.body[req.body.primaryid])

			getFile = (req) ->
				docpad.getFile(relativePath: (if typeof req == 'string' then req else getFilenameFromReq(req)))

			updateFile = (file, req, res, successMsg = 'Updated') ->
				# Setup and error out if in bad state
				unless file
					return res.send(success: false, message: 'File does not exist')

				# Add any custom meta attributes
				for own key, value of req.body
					file.setMeta(key, value)  unless key in ['filename', 'primaryid', 'content']

				# Return the file to the user
				# This will trigger regeneration
				file.writeSource {cleanAttributes: true}, (err) ->
					console.log err  if err
					res.send(success: !err, message: err or successMsg, filename: file.get('fullPath').replace(fsPath, ''))

			# DELETE:
			# Remove an existing file
			server.delete "#{config.channel}/*" , (req, res) ->
				# Setup and error out if in bad state
				unless filename = getFilenameFromReq(req)
					return res.send(success: false, message: 'Please specify a filename')
				file = getFile(filename)
				unless file
					return res.send(success: false, message: 'File does not exist')

				# If all good, remove the file from the DB
				database.remove(file)
				file.delete (err) ->
                	console.log err  if err
                	res.send(success: !err, message: err or 'Deleted', filename: filename)

			# UPLOAD
			# Handle file uploads posted to /upload
			server.post "#{config.channel}/upload", (req, res) ->
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

			# CREATE or UPDATE
			# Create or update a file in the docpad database (as well as on the file system) via the REST API
			server.post "#{@config.channel}/*" , (req, res) ->
				if req.body.update
					return updateFile(getFile(req), req, res)

				# Get the filename
				unless filename = getFilenameFromReq(req)
					return res.send(success: false, message: 'Please specify a filename')

				# Set up our new document
				documentAttributes =
					data: req.body.content or ''
					fullPath: fsPath + findUniqueFilename(filename)

				# Create the document, inject document helper and add the document to the database
				document = docpad.createDocument(documentAttributes)

				# Inject helper and add to the db
				config.injectDocumentHelper?.call(me, document)
				database.add(document)

				# Add metadata
				updateFile(document, req, res, 'Saved')


			# A helper function that takes a docpad file and outputs an object with desired fields from the file
			fetchFields = (req, file) ->
				# Return immediately if the user wants all attributes
				req.query.af = req.query.af or req.query.fields or req.query.additionalFields or req.query.additionalfields
				if (Array.isArray req.query.af and req.query.af[0] is 'all') or req.query.af is 'all'
					return file.attributes

				# Defaults
				meta = file.meta
				meta.content = file.attributes.content or meta.content
				fields =
					filename: file.attributes.id
					url: file.attributes.url
					meta: file.meta
					contentType: file.attributes.outContentType
					encoding: file.attributes.encoding
					renderedContent: file.attributes.contentRendered

				unless Array.isArray req.query.af
					req.query.af = if req.query.af then [req.query.af] else []

				# Add additional fields the user has requested to the output
				len = req.query.af.length
				while len--
					field = req.query.af[len]
					fields[field] = file.attributes[field]

				# Return the data
				return fields

			# A helper function that gets a collection based on request filters and sorting options
			getFilteredCollection = (req) ->
				filter = {}
				sort = {}
				filterObject = if req.query.filter then JSON.parse(req.query.filter) else {}

				# Beware: the filter is applied on the attributes of the file, not the META which is what the user is getting!
				for own key of filterObject
					if Array.isArray(filterterObject[key])
						filter[key] = $in: filterObject[key]
					else
						filter[key] = filterObject[key]

				# Add our special filters
				for own key of req.query._filter
					filter[key] = req.query._filter[key]
				sort[req.query.sort or 'date'] = req.query.sortOrder or -1
				collection = if req.params.type and req.params.type.toLowerCase() != 'all' then docpad.getCollection(req.params.type or 'documents') else database

				# Return the data
				result = collection?.findAll(filter, sort) or {models:[]}
				return result

			### READ
				a method to get files from the docpad database
				Usage:
					/{collectionName}/  												Get a listing of the {collectionName} collection
					/{collectionName}/{fileName}  										See info about a specific file
					/{collectionName}[/relative/path/]  								Get a listing of the {collectionName} collection filtered by relativePath
				Optional Query String Params:
					mime            eg  String: image                                   Searches the mime type
					pageSize        eg  Number: 10        Default: 10					The size of listing page returned. Set to falsey for no limit.
					page            eg  Number: 10										The listing page number to be returned
					filter          eg  JSON: {'relativePath': $startsWith: 'a' }		A Query Engine filter to be applied to the collection being retuned
				Notes:
					DocPad already provides a few collection names, including: database/all, documents, files, layouts, html, stylesheet
			###
			server.all "#{@config.channel}/:collectionName/*", (req,res) ->
				# Prepare
				files = null
				queryOpts = null
				sortOpts = null
				pageOpts = null
				findMethod = 'findAll'

				# Fetch the file
				files = docpad.getCollection(req.params.collectionName)

				# Add filter to query
				if req.query.filter
					try
						queryOpts = JSON.parse(req.query.filter)
					catch err
						return res.send(
							success: false
							message: "Failed to parse your custom filter: #{JSON.stringify(req.query.filter)}"
						)

				# Add mime to query
				if req.query.mime
					queryOpts ?= {}
					if req.query.mime in ['images', 'image']
						queryOpts.outContentType = $startsWith: 'image/'
					else if req.query.mime in ['videos', 'video']
						queryOpts.outContentType = $startsWith: 'video/'
					else
						queryOpts.outContentType = req.query.mime

				# Add paging
				if req.query.page
					pageOpts.page = req.query.page
					pageOpts.size = req.query.pageSize ? 10
				else
					# Adjust the find method
					findMethod = 'findOne'  if req.query.pageSize is 1

				# Perform filters
				files = files[findMethod](queryOpts, sortOpts, pageOpts)  if queryOpts

				# LIST
				if req.method is 'get'
					# Fetch the result
					result = data.toJSON()

					# Send the result
					return res.send(result)

				# UPDATE
				else if req.method in ['put', 'post', 'delete']
					#

				# UNKNOWN
				else
					return res.send(
						success: false
						message: "Unknown method #{req.method}"
					)

			# Chain
			@
// Import and register all your controllers from the importmap via controllers/**/*_controller
//
// `eagerLoadControllersFrom` auto-discovers and registers every `*_controller.js`
// under `app/javascript/controllers/` (including cmdk_controller). No manual
// `application.register` is needed — the file's name → identifier convention
// (cmdk_controller → "cmdk") is handled automatically.
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

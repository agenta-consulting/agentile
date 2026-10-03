I want to build a web app that replaces the Airtable Store. It will provide the same schema to begine with (with Rails defailt colums as extra: id, created_at, updated_at, etc). 

The app will act as the data store for agentile skills to sore and retrrieve data from. SOme busines logic could be moved to the web app. Whatever the best interface for Claude agentile skills to interact with the data, you figure that out. MCP or API or whatever. 

It needs to handle meultiuple users, multiple projects. A Project can be shared with other users. For example, Danny and I will share the Tekmore project. Here's get the chance to build in role based access control, kust alight tough to begin with (use the pundit ruby gem to implement a role policy setup: https://www.railscarma.com/blog/mastering-authorization-in-rails-with-pundit-gem/)

I want the app based on the demo parctice management app. That look and feel is great. Choose a different colour scheme if you please, I don't mind. I want the same kind of stuff the airtable base gives us: Inbox (with LLM assisten generation of the inbox item, just like if I did it from the claude console with the capture skill), Specs, Outcomes, Runs, Checkpoints. 

sqlite. Daisy Stack VueJS components. 

I want pills to be coloured, pick a colour scheme that works well with the app's overall look and feel and have consisten concepts coloured consistently. for instance: SPIKE should be the same colour in the multiple places it's used.

User Jev wherever you can do add classification or checkpoint logic or whatever you can think of that would help move business logic from the agentile skill into the web app and be faster. Look at ~/lab/jev for use case ideas. Use those ruby gems that app uses too.. For LLM functionality, use Ruby LLM gem. 

Be sure to use idomatic DaisySteack where you can. Make use of the two way socket comms when it makes sense. 

User management. the standard Devise gem approach. Invitation only at this point.

With business logic moving from Agentile skills to the web app, we might be able to improve or move the mutexes around claiming a spec etc.

With this app, we'll take Agentile from single user to App only. The App will become the only user store it supports.

A project should have a dashboard. We'll be able to put stats, workgin in progress, whats up next and all that kind of stuff on the dashboard.

There should also be an overall dashboard for each user that shows their projkects and some rolled up info on each, whatever we think works best. Even though build agents will run locally on our machines, I will want some indications of which projects have build sessions requiring input or waiting for a response, and inside a project, show which sessions are waiting for input or have completed.

This webapp should have it's own repo (with a directory inside `~/projects/agentile`) I think we can call it Agentile Projects. I'll register the subdomain agentile-projects.agentaconsulting.com

We'll also redo (almost completely) the https://agentile.agentaconsulting.com/ website. It should change to reflect how agentile now works. There's a big emphasis now on two separate loops/workflows. capture and shaping which is where Humans and agents can frontload effort into helping the next loop (build and verify) be maore automatic.

Build it out as a prototype so completely that we will be able to cut over from storing in Airtable to this new up easily. You'll need to build (on a branch) a new version of Agentile so all the skills and store stuff points at the new site.

plan it, ask any questions, anythign you think I have missed befiore you go ahead and build the prototype

require "bundler/capistrano"
server "127.0.0.1", :web, :app, :db, primary: true

set :application, "testapp"
set :user, "vagrant"

set :scm, "git"
set :repository, "git@github.com:rdavila/template_app.git"
set :branch, "demo"
set :deploy_to, "/u/apps/#{application}"
set :deploy_via, :remote_cache
set :use_sudo, false
#set :shared_children, shared_children + %w{public/uploads}

default_run_options[:pty] = true
ssh_options[:forward_agent] = true
ssh_options[:port] = 2222

after "deploy", "deploy:cleanup", "deploy:assets:clean" # keep only the last 5 releases
# This is necessary to avoid cap deploy:cold failing duw to missing symlink
before "deploy:assets:precompile", "deploy:create_symlink"

namespace :deploy do
  %w[start stop restart].each do |command|
    desc "#{command} unicorn server"
    task command, roles: :app, except: {no_release: true} do
      sudo "kill -HUP `cat /usr/local/nginx/logs/nginx.pid`"
      sudo "/etc/init.d/unicorn restart"
    end
  end

  task :setup_config, roles: :app do
    sudo "ln -nfs #{current_path}/config/nginx.conf /usr/local/nginx/sites-enabled/#{application}"
    run "mkdir -p #{shared_path}/config"
    put File.read("config/database.yml.example"), "#{shared_path}/config/database.yml"
    puts "Now edit the config files in #{shared_path}."
  end
  after "deploy:setup", "deploy:setup_config"

  task :symlink_config, roles: :app do
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
  end
  after "deploy:finalize_update", "deploy:symlink_config"

  desc "Make sure local git is in sync with remote."
  task :check_revision, roles: :web do
    unless `git rev-parse HEAD` == `git rev-parse origin/#{branch}`
      puts "WARNING: HEAD is not the same as origin/#{branch}"
      puts "Run `git push` to sync changes."
      exit
    end
  end
  before "deploy", "deploy:check_revision"

  namespace :assets do
    task :precompile, :roles => :web, :except => { :no_release => true } do
      from = source.next_revision(current_revision)
      if capture("cd #{latest_release} && #{source.local.log(from)} vendor/assets/ app/assets/ | wc -l").to_i > 0
        run %Q{cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} #{asset_env} assets:precompile}
      else
        logger.info "Skipping asset pre-compilation because there were no asset changes"
        end
    end
  end
end

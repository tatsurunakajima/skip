# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008-2009 TIS Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

class CollaborationApp::GroupController < ApplicationController
  def feed
    CollaborationApp.new(params[:app_name]).resource(current_user, "#{params[:path]}?skip_gid=#{params[:gid]}") do |result, body|
      if result
        feed_items = CollaborationApp.sorted_feed_items(body)
        render :partial => 'collaboration_app/shared/feed', :locals => {:feed_items => feed_items}, :layout => false
      else
        render :text => _('取得できませんでした。')
      end
    end
  end
end

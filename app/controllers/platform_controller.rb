# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008 TIS Inc.
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

require 'openid/extensions/ax'

class PlatformController < ApplicationController
  layout false
  skip_before_filter :sso, :login_required, :prepare_session
  skip_after_filter  :remove_message

  before_filter :require_not_login, :except => [:logout]

  def index
    img_files = Dir.glob(File.join(RAILS_ROOT, "public", "custom", "images", "titles", "background*.{jpg,png,jpeg}"))
    @img_name = File.join("titles", File.basename(img_files[rand(img_files.size)]))
  end

  def require_login
  end

  # ログイン処理（トップからと、require_loginからの両方からpostされる）
  # 認証後は、戻り先がある場合はそちらへ、なければデフォルトはSKIPへ遷移
  def login
    if using_open_id?
      login_with_open_id
    else
      if params[:login] and user = User.auth(params[:login][:key], params[:login][:password])
        reset_session
        session[:user_code] = user.code

        redirect_to_back_or_root
      else
        flash[:auth_fail_message] ||={ "message" => _("ログインに失敗しました。"), "detail" => _("下部に記載されているお問い合わせ先にご連絡下さい。")}
        if request.env['HTTP_REFERER']
          redirect_to :back
        else
          redirect_to :action => :index
        end
      end
    end
  end

  # ログアウト
  def logout
    reset_session
    notice = _('You are now logged out.')
    notice = notice + "<br>" + _('You had been retired.') unless params[:message].blank?
    flash[:notice] = notice

    redirect_to login_mode?(:fixed_rp) ? "#{INITIAL_SETTINGS['fixed_op_url']}logout" : {:action => "index"}
  end

  private
  def require_not_login
    if current_user
      unless current_user.unused?
        redirect_to_back_or_root
      else
        redirect_to :controller => :portal, :action => :index
      end
    end
  end

  def login_with_open_id
    session[:return_to] = params[:return_to] if !params[:return_to].blank? and params[:open_id_complete].blank?
    authenticate_with_open_id do |result, identity_url, registration|
      if result.successful?
        unless identifier = OpenidIdentifier.find_by_url(identity_url)
          create_user_from(identity_url, registration)
        else
          return_to = session[:return_to]
          reset_session

          user = identifier.user_with_unused
          session[:user_code] = user.code

          redirect_to_back_or_root(return_to)
        end
      else
        set_error_message_form_result_and_redirect(result)
      end
    end
  end

  def create_user_from(identity_url, registration)
    if login_mode?(:fixed_rp) and identity_url.include?(INITIAL_SETTINGS['fixed_op_url'])
      user = User.create_with_identity_url(identity_url, create_user_params(registration))
      if user.valid?
        reset_session
        session[:user_code] = user.code

        redirect_to :controller => :portal
      else
        set_error_message_from_user_and_redirect(user)
      end
    elsif login_mode?(:free_rp)
      session[:identity_url] = identity_url

      redirect_to :controller => :portal, :action => :index
    else
      set_error_message_not_create_new_user_and_redirect
    end
  end


  def redirect_to_back_or_root(return_to = params[:return_to])
    return_to = return_to ? URI.encode(return_to) : nil
    redirect_to (return_to and !return_to.empty?) ? return_to : root_url
  end

  def create_user_params registration
    user_attribute = {}
    INITIAL_SETTINGS['ax_fetchrequest'].each do |a|
      user_attribute[a[1].to_sym] = registration.data[a[0]][0]
    end
    user_attribute
  end

  def set_error_message_form_result_and_redirect(result)
    error_messages = {
      :missing      => [_("OpenIDサーバーが見つかりませんでした。"), _("正しいOpenID URLを入力してください。")] ,
      :canceled     => [_("キャンセルされました。"), _("このサーバへの認証を確認してください") ],
      :failed       => [_("認証に失敗しました。"), "" ],
      :setup_needed => [_("内部エラーが発生しました。"), _("管理者に連絡してください。") ]
    }
    set_error_message_and_redirect error_messages[result.instance_variable_get(:@code)], {:controller => :platform, :action => :login}
  end

  def set_error_message_from_user_and_redirect(user)
    set_error_message_and_redirect [_("ユーザの登録に失敗しました。"), _("管理者に連絡してください。<br/>%{msg}")%{:msg => user.errors.full_messages}], :action => :index
  end

  def set_error_message_not_create_new_user_and_redirect
    set_error_message_and_redirect [_("そのOpenIDは、登録されていません。"), _("ログイン後管理画面でOpenID URLを登録後ログインしてください。")], :action => :index
  end

  def set_error_message_and_redirect(message, url)
    flash[:auth_fail_message] = {
      "message" => message.first,
      "detail" => message.last
    }
    redirect_to url
  end

  # -----------------------------------------------
  # over ride open_id_authentication to use OpenID::AX
  def add_simple_registration_fields(open_id_request, fields)
    axreq = OpenID::AX::FetchRequest.new
    requested_attrs = INITIAL_SETTINGS['ax_fetchrequest']
    requested_attrs.each { |a| axreq.add(OpenID::AX::AttrInfo.new(a[0], a[1], a[2] || false, a[3] || 1)) }
    open_id_request.add_extension(axreq)
    open_id_request.return_to_args['did_ax'] = 'y'
  end

  def complete_open_id_authentication
    params_with_path = params.reject { |key, value| request.path_parameters[key] }
    params_with_path.delete(:format)
    open_id_response = timeout_protection_from_identity_server { open_id_consumer.complete(params_with_path, requested_url) }
    identity_url     = normalize_url(open_id_response.endpoint.claimed_id) if open_id_response.endpoint and open_id_response.endpoint.claimed_id
    case open_id_response.status
    when OpenID::Consumer::SUCCESS
      yield Result[:successful], identity_url, OpenID::AX::FetchResponse.from_success_response(open_id_response)
    when OpenID::Consumer::CANCEL
      yield Result[:canceled], identity_url, nil
    when OpenID::Consumer::FAILURE
      yield Result[:failed], identity_url, nil
    when OpenID::Consumer::SETUP_NEEDED
      yield Result[:setup_needed], open_id_response.setup_url, nil
    end
  end
  # -----------------------------------------------
end


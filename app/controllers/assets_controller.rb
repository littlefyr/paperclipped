class AssetsController < ApplicationController
  
  make_resourceful do 
    actions :all
    response_for :index do |format|
      format.html { render }
      format.js {
        if params[:asset_page]
          @asset_page = Page.find(params[:asset_page])
          render :partial => 'assets/search_results.html.haml', :layout => false
        else
          render :partial => 'assets/asset_table.html.haml', :layout => false
        end
      }
    end
    after :create do
      if params[:page]
        @page = Page.find(params[:page])
        @asset.pages << @page
      end
    end
    
    after :update do
      ResponseCache.instance.clear
    end
    
    response_for :update do |format|
      format.html { 
        flash[:notice] = "Asset successfully updated."
        redirect_to(params[:continue] ? edit_asset_path(@asset) : assets_path) 
      }
    end
    response_for :create do |format|
      format.html { 
        flash[:notice] = "Asset successfully uploaded."
        redirect_to(@page ? edit_admin_page_url(@page) : (params[:continue] ? edit_asset_path(@asset) : assets_path)) 
      }
      format.js {
        responds_to_parent do
          render :update do |page|
            page.call('Asset.ChooseTabByName', 'page-attachments')
            page.insert_html :bottom, "attachments", :partial => 'assets/asset', :object => @asset, :locals => {:dom_id => "attachment_#{@asset.id}" }    # can i be bothered to find the attachment id?
            page.call('Asset.AddAsset', "attachment_#{@asset.id}")
            # we ought to reinitialise the sortable attachments too
            page.visual_effect :highlight, "attachment_#{@asset.id}" 
            page.call('Asset.ResetForm')
          end
        end          
      }
    end
     
  end
  
  def regenerate_thumbnails
    if request.post? 
      unless params[:id]
        @assets = Asset.find(:all)
        @assets.each do |asset|
          asset.asset.reprocess!
          asset.save
        end
        flash[:notice] = "Thumbnails successfully refreshed."
        redirect_to assets_path
      else
        @asset = Asset.find(params[:id])
        @asset.asset.reprocess!
        @asset.save
        flash[:notice] = "Thumbnails successfully refreshed."
        redirect_to edit_asset_path(@asset)
      end
    else
      render "Do not access this url directly"
    end
    
  end
  
  def add_bucket
    @asset = Asset.find(params[:id])
    if (session[:bucket] ||= {}).key?(@asset.asset.url)
      render :nothing => true and return
    end
    asset_type = @asset.image? ? 'image' : 'link'
    session[:bucket][@asset.asset.url] = { :thumbnail => @asset.thumbnail(:thumbnail), :id => @asset.id, :title => @asset.title, :type => asset_type }

    render :update do |page|
      page[:bucket_list].replace_html "#{render :partial => 'bucket'}"
    end
  end
  
  def clear_bucket
    session[:bucket] = nil
    render :update do |page|
      page[:bucket_list].replace_html '<li><p class="note"><em>Your bucket is empty.</em></p></li>'
    end
  end
  
  def attach_asset
    @asset = Asset.find(params[:asset])
    @page = Page.find(params[:page])
    @page.assets << @asset unless @page.assets.include?(@asset)
    ResponseCache.instance.clear
    render :update do |page|
      page[:attachments].replace_html "#{render :partial => 'page_assets', :locals => {:page => @page}}"
    end
    
  end
  
  def remove_asset    
    @asset = Asset.find(params[:asset])
    @page = Page.find(params[:page])
    @page.assets.delete(@asset)
    ResponseCache.instance.clear
    render :nothing => true
  end
  
  def reorder
    params[:attachments].each_with_index do |id,idx| 
      page_attachment = PageAttachment.find(id)
      page_attachment.position = idx+1
      page_attachment.save
    end
    ResponseCache.instance.clear
    render :nothing => true
  end
  
  def remove 
    @asset = Asset.find(params[:id])
    # This is a temporary measure! It is not very RESTful, but I like the confirm page... 
    if request.post?
      session[:bucket].delete(@asset.asset.url) if session[:bucket] && session[:bucket].key?(@asset.asset.url)
      @asset.destroy
      ResponseCache.instance.clear
      redirect_to assets_path
    end 
  end
  
  protected
  
    def current_objects
      unless params['search'].blank?
        term = params['search'].downcase

        search_cond_sql = []
        cond_params = {}
      
        search_cond_sql << 'LOWER(asset_file_name) LIKE (:term)'
        search_cond_sql << 'LOWER(title) LIKE (:term)'
        search_cond_sql << 'LOWER(caption) LIKE (:term)'

        cond_sql = search_cond_sql.join(" or ")
      
        cond_params[:term] = "%#{term}%"
      
        @conditions = [cond_sql, cond_params]
      else
        @conditions = []
      end
      
      @file_types = params[:filter].blank? ? [] : params[:filter].keys

      if not @file_types.empty?
        Asset.paginate_by_content_types(@file_types, :all, :conditions => @conditions, :order => 'created_at DESC', 
          :page => params[:page], :per_page => 10, :total_entries => count_by_conditions)
      else
        Asset.paginate(:all, :conditions => @conditions, :order => 'created_at DESC', :page => params[:page], :per_page => 10)
      end
    end
    
    def count_by_conditions
      type_conditions = @file_types.blank? ? nil : Asset.types_to_conditions(@file_types.dup).join(" OR ")
      @count_by_conditions ||= @conditions.empty? ? Asset.count(:all, :conditions => type_conditions) : Asset.count(:all, :conditions => @conditions)
    end

end

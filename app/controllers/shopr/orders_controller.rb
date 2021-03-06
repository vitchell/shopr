module Shopr
  class OrdersController < Shopr::ApplicationController
    before_action { @active_nav = :orders }
    before_action { params[:id] && @order = Shopr::Order.find(params[:id]) }

    def index
      @query = Shopr::Order.ordered.received.includes(order_items: :ordered_item).page(params[:page]).search(params[:q])
      @orders = @query.result
    end

    def new
      @order = Shopr::Order.new
      @order.order_items.build(ordered_item_type: 'Shopr::Product')
    end

    def create
      Shopr::Order.transaction do
        @order = Shopr::Order.new(safe_params)
        @order.status = 'confirming'

        if safe_params[:customer_id]
          @customer = Shopr::Customer.find safe_params[:customer_id]
          @order.first_name = @customer.first_name
          @order.last_name = @customer.last_name
          @order.company = @customer.company
          @order.email_address = @customer.email
          @order.phone_number = @customer.phone
          if @customer.addresses.billing.present?
            billing = @customer.addresses.billing.first
            @order.billing_address1 = billing.address1
            @order.billing_address2 = billing.address2
            @order.billing_address3 = billing.address3
            @order.billing_address4 = billing.address4
            @order.billing_postcode = billing.postcode
            @order.billing_country_id = billing.country_id
          end
          if @customer.addresses.delivery.present?
            delivery = @customer.addresses.delivery.first
            @order.delivery_address1 = delivery.address1
            @order.delivery_address2 = delivery.address2
            @order.delivery_address3 = delivery.address3
            @order.delivery_address4 = delivery.address4
            @order.delivery_postcode = delivery.postcode
            @order.delivery_country_id = delivery.country_id
          end
        end

        if !request.xhr? && @order.save
          @order.confirm!
          redirect_to @order, flash: { notice: t('shopr.orders.create_notice') }
        else
          @order.order_items.build(ordered_item_type: 'Shopr::Product')
          render action: 'new'
        end
      end
    rescue Shopr::Errors::InsufficientStockToFulfil => e
      flash.now[:alert] = t('shopr.orders.insufficient_stock_order', out_of_stock_items: e.out_of_stock_items.map { |t| t.ordered_item.full_name }.to_sentence)
      render action: 'new'
    end

    def show
      @payments = @order.payments.to_a
    end

    def update
      @order.attributes = safe_params
      if !request.xhr? && @order.update_attributes(safe_params)
        redirect_to @order, flash: { notice: t('shopr.orders.update_notice') }
      else
        render action: 'edit'
      end
    end

    def search
      index
      render action: 'index'
    end

    def accept
      @order.accept!(current_user)
      redirect_to @order, flash: { notice: t('shopr.orders.accept_notice') }
    rescue Shopr::Errors::PaymentDeclined => e
      redirect_to @order, flash: { alert: e.message }
    end

    def reject
      @order.reject!(current_user)
      redirect_to @order, flash: { notice: t('shopr.orders.reject_notice') }
    rescue Shopr::Errors::PaymentDeclined => e
      redirect_to @order, flash: { alert: e.message }
    end

    def ship
      @order.ship!(params[:consignment_number], current_user)
      redirect_to @order, flash: { notice: t('shopr.orders.ship_notice') }
    end

    def despatch_note
      render layout: 'shopr/printable'
    end

    private

    def safe_params
      params[:order].permit(
        :customer_id,
        :first_name, :last_name, :company,
        :billing_address1, :billing_address2, :billing_address3, :billing_address4, :billing_postcode, :billing_country_id,
        :separate_delivery_address,
        :delivery_name, :delivery_address1, :delivery_address2, :delivery_address3, :delivery_address4, :delivery_postcode, :delivery_country_id,
        :delivery_price, :delivery_service_id, :delivery_tax_amount,
        :email_address, :phone_number,
        :notes,
        order_items_attributes: %i[ordered_item_id ordered_item_type quantity unit_price tax_amount id weight]
      )
    end
  end
end

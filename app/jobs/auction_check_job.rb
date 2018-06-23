class AuctionCheckJob < ApplicationJob

  queue_as :default
  require 'typhoeus'
  require 'objspace'
  require 'date'
  require 'peddler'
  require 'csv'

  rescue_from(StandardError) do |exception|
   # Do something with the exception
   logger.debug("====== Error ======")
   logger.debug(exception)
  end


  def perform(cuser)
    # Do something later
    logger.debug("Process Start")
    #ua = CSV.read('app/others/User-Agent.csv', headers: false, col_sep: "\t")
    stock = Stock.where(email: cuser)
    tag = stock.pluck(:sku)
    counter = 0
    tcounter = 0
    account = Account.find_by(user: cuser)
    token = account.cw_api_token
    rid = account.cw_room_id
    std = Time.now.to_s
    msg = "監視開始\n処理開始日時：" + std + "\n処理対象：" + tag.length.to_s + "件"
    logger.debug(msg)
    msend(msg, token, rid)
    tag.each do |org_sku|
      header = org_sku.slice(0,3)
      sku = org_sku.slice(3..-1)
      if header == 'ya-' then
        logger.debug("=== ヤフオク監視 ===")
        if account.yahoo == true then
          url = 'https://page.auctions.yahoo.co.jp/jp/auction/' + sku
          logger.debug(url)
          charset = nil
          rt = rand(10)*0.1+0.2
          sleep(rt)
          begin
            logger.debug("Access URL")
            ua = "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.63 Safari/537.36"
            request = Typhoeus::Request.new(url, headers: {"User-Agent" => ua})
            request.run
            html = request.response.body
            doc = Nokogiri::HTML.parse(html, nil, charset)
            isValid = true
            auction = doc.xpath('//p[@class="ptsFin"]')[0] #オークションが終了かチェック
            logger.debug("Get Html body")
            quantity = 0
            expired = false
            if auction == nil then
              logger.debug('Item is on sale')
              title = doc.xpath('//h1[@class="ProductTitle__text"]')[0].inner_text
              title = title.strip
              tc = doc.xpath('//div[@class="Price Price--current"]')[0]

              if tc != nil then
                cPrice = tc.xpath('dl/dd[@class="Price__value"]/text()')[0]
                cPrice = cPrice.inner_text.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
              else
                cPrice = 0
              end

              tb = doc.xpath('//div[@class="Price Price--buynow"]')[0]
              if tb != nil then
                bPrice = tb.xpath('dl/dd[@class="Price__value"]/text()')[0]
                bPrice = bPrice.inner_text.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
              else
                bPrice = 0
              end

              bit = doc.xpath('//li[@class="Count__count"]')[0]
              if bit != nil then
                bit = bit.xpath('dl/dd[@class="Count__number"]')[0].inner_text.to_i
              else
                bit = 0
              end

              rest = doc.xpath('//li[@class="Count__count Count__count--sideLine"]')[0]
              if rest != nil then
                restunit = rest.xpath('dl/dd[@class="Count__number"]/span[@class="Count__unit"]')[0].inner_text
                rest = rest.xpath('dl/dd[@class="Count__number"]/text()')[0].inner_text

                case restunit
                when "日" then
                  rest = rest.to_i * 60 * 24
                when "時間" then
                  rest = rest.to_i * 60
                when "分" then
                  rest = rest.to_i
                else
                  rest = 0
                end
              else
                rest = 0
              end

              if bit == 0 then
                bcheck = true
              else
                bcheck = false
              end

              if rest != 0 then
                rcheck = true
              else
                rcheck = false
              end
              quantity = 1
            else #オークションが終了の場合
              logger.debug("Auction is end")
              isValid = false
              cPrice = doc.xpath('//tr[@class="elAucPriceRw"]')[0]
              if cPrice != nil then
                taxin = cPrice.xpath('//p[@class="decTxtTaxIncPrice"]')[0].inner_text
                if taxin == '（税0円）'  then
                  cPrice = cPrice.xpath('//p[@class="decTxtAucPrice"]')[0].inner_text
                  cPrice = cPrice.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
                else
                  cPrice = cPrice.xpath('//p[@class="decTxtAucPrice"]')[0].inner_text
                  cPrice = cPrice[3..(cPrice.length-2)]
                  cPrice = cPrice.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
                end
              else
                cPrice = 0
              end

              bPrice = doc.xpath('//tr[@class="elBidOrBuyPriceRw"]')[0]
              if bPrice != nil then
                taxin = bPrice.xpath('//p[@class="decTxtTaxIncPrice"]')[0].inner_text
                if taxin == '（税0円）'  then
                  bPrice = bPrice.xpath('//p[@class="decTxtBuyPrice"]')[0].inner_text
                  bPrice = bPrice.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
                else
                  bPrice = bPrice.xpath('//p[@class="decTxtBuyPrice"]')[0].inner_text
                  bPrice = bPrice[3..(bPrice.length-2)]
                  bPrice = bPrice.gsub(/\,/,"").gsub(/円/,"").gsub(/ /,"").to_i
                end
              else
                bPrice = 0
              end

              bit = doc.xpath('//b[@property="auction:Bids"]')[0].inner_text.to_i
              rest = 0
              if bit == 0 then
                bcheck = true
              else
                bcheck = false
              end
              rcheck = false
            end

          rescue => e
            logger.debug("Error!!\n")
            logger.debug(e)
            isValid = false

            cPrice = 0
            bPrice = 0
            bit = 0
            rest = 0
            bcheck = false
            rcheck = false
            expired = true
          end

          logger.debug('==== Start updating table ====')
          progress = ""
          progress = "\nParameter\n"
          progress = progress + "email:" + cuser + "\n"
          progress = progress + "current_price:" + cPrice.to_s + "\n"
          progress = progress + "fixed_price:" + bPrice.to_s + "\n"
          progress = progress + "accsess_date:" + Time.now.to_s + "\n"
          progress = progress + "vailidity:" + isValid.to_s + "\n"
          progress = progress + "title:" + title.to_s + "\n"
          logger.debug(progress)

          Stock.find_or_initialize_by(email: cuser, sku: org_sku).update(
            title: title,
            current_price: cPrice,
            fixed_price: bPrice,
            access_date: Time.now,
            quantity: quantity,
            validity: isValid,
            expired: expired
          )
          ObjectSpace.each_object(ActiveRecord::Relation).each(&:reset)
          GC.start
          logger.debug('Process end')
          counter = counter + 1
          tcounter = tcounter + 1
          if tcounter > 1000 then
            msg = "在庫監視途中経過\n処理開始日時：" + std + "\n処理対象：" + tag.length.to_s + "件"
            msg = msg + "\n在庫監視途中経過\n中間経過日時：" + Time.now.to_s + "\n処理済み：" + counter.to_s + "件"
            msend(msg, token, rid)
            tcounter = 0
          end
        else
          logger.debug("監視対象外")
        end
      elsif header == 'me-' then
        logger.debug("=== メルカリ ===")
        url = 'https://item.mercari.com/jp/' + sku
        logger.debug(url)
        if account.mercari == true then
          begin
            logger.debug("Access URL")
            ua = "Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.63 Safari/537.36"
            #request = Typhoeus::Request.new(url, headers: {"User-Agent" => ua}, follow_location: true)
            #request.run
            #html = request.response.body

            html = open(url, "User-Agent" => ua) do |f|
              f.read # htmlを読み込んで変数htmlに渡す
            end

            doc = Nokogiri::HTML.parse(html, nil, charset)
            expired = false
            title =  doc.xpath('//h2[@class="item-name"]')[0].inner_text
            price = doc.xpath('//span[@class="item-price bold"]')[0].inner_text
            price = price.gsub(/\,/,"").gsub(/\\/,"").gsub(/ /,"").to_i
            sold = doc.xpath('//div[@class="item-sold-out-badge"]')
            if sold == nil then
              isValid = false
              logger.debug("=== メルカリ 在庫あり！===")
            else
              isValid = true
              logger.debug("=== メルカリ 在庫切れ===")
            end
          rescue => e
            logger.debug("Error!!\n")
            logger.debug(e)
            isValid = false
            cPrice = 0
            bPrice = 0
            bit = 0
            rest = 0
            bcheck = false
            rcheck = false
            expired = true
          end
          logger.debug('==== Start updating table ====')
          progress = ""
          progress = "\nParameter\n"
          progress = progress + "email:" + cuser + "\n"
          progress = progress + "current_price:" + cPrice.to_s + "\n"
          progress = progress + "fixed_price:" + bPrice.to_s + "\n"
          progress = progress + "accsess_date:" + Time.now.to_s + "\n"
          progress = progress + "vailidity:" + isValid.to_s + "\n"
          progress = progress + "title:" + title.to_s + "\n"
          logger.debug(progress)

          Stock.find_or_initialize_by(email: cuser, sku: org_sku).update(
            title: title,
            current_price: cPrice,
            fixed_price: bPrice,
            access_date: Time.now,
            quantity: quantity,
            validity: isValid,
            expired: expired
          )
          ObjectSpace.each_object(ActiveRecord::Relation).each(&:reset)
          GC.start
          logger.debug('Process end')
          counter = counter + 1
          tcounter = tcounter + 1
          if tcounter > 1000 then
            msg = "在庫監視途中経過\n処理開始日時：" + std + "\n処理対象：" + tag.length.to_s + "件"
            msg = msg + "\n在庫監視途中経過\n中間経過日時：" + Time.now.to_s + "\n処理済み：" + counter.to_s + "件"
            msend(msg, token, rid)
            tcounter = 0
          end
        else
          logger.debug("監視対象外")
        end
      elsif header == 'su-' then
        logger.debug("=== 駿河屋 ===")
        url = 'https://www.suruga-ya.jp/product/detail/' + sku
        logger.debug(url)
        if account.surugaya == true then
          begin
            logger.debug("Access URL")
            request = Typhoeus::Request.new(url)
            request.run
            html = request.response.body
            doc = Nokogiri::HTML.parse(html, nil, charset)
            isValid = true
            expired = false
            title = doc.xpath('//h2[@id="item_title"]/text()')[2].inner_text
          rescue => e
            logger.debug("Error!!\n")
            logger.debug(e)
            isValid = false
            cPrice = 0
            bPrice = 0
            bit = 0
            rest = 0
            bcheck = false
            rcheck = false
            expired = true
          end
          logger.debug('==== Start updating table ====')
          progress = ""
          progress = "\nParameter\n"
          progress = progress + "email:" + cuser + "\n"
          progress = progress + "current_price:" + cPrice.to_s + "\n"
          progress = progress + "fixed_price:" + bPrice.to_s + "\n"
          progress = progress + "accsess_date:" + Time.now.to_s + "\n"
          progress = progress + "vailidity:" + isValid.to_s + "\n"
          progress = progress + "title:" + title.to_s + "\n"
          logger.debug(progress)

          Stock.find_or_initialize_by(email: cuser, sku: org_sku).update(
            title: title,
            current_price: cPrice,
            fixed_price: bPrice,
            access_date: Time.now,
            quantity: quantity,
            validity: isValid,
            expired: expired
          )
          ObjectSpace.each_object(ActiveRecord::Relation).each(&:reset)
          GC.start
          logger.debug('Process end')
          counter = counter + 1
          tcounter = tcounter + 1
          if tcounter > 1000 then
            msg = "在庫監視途中経過\n処理開始日時：" + std + "\n処理対象：" + tag.length.to_s + "件"
            msg = msg + "\n在庫監視途中経過\n中間経過日時：" + Time.now.to_s + "\n処理済み：" + counter.to_s + "件"
            msend(msg, token, rid)
            tcounter = 0
          end
        else
          logger.debug("監視対象外")
        end
      end
    end
    msg = "在庫監視終了しました\n処理終了日時：" + Time.now.to_s + "\n処理対象：" + tag.length.to_s + "件"
    msend(msg, token, rid)
  end

  def msend(message, api_token, room_id)
    base_url = "https://api.chatwork.com/v2"
    endpoint = base_url + "/rooms/" + room_id  + "/messages"
    request = Typhoeus::Request.new(
      endpoint,
      method: :post,
      params: { body: message },
      headers: {'X-ChatWorkToken'=> api_token}
    )
    request.run
    res = request.response.body
    logger.debug(res)
  end

end

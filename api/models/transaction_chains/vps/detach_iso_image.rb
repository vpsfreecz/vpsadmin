module TransactionChains
  class Vps::DetachIsoImage < ::TransactionChain
    label 'ISO-'

    def link_chain(vps)
      lock(vps)

      raise 'No ISO image to detach' if vps.iso_image.nil?

      append_t(Transactions::Vps::DetachIsoImage, args: [vps, vps.iso_image])

      append_t(Transactions::Vps::Define, args: [vps], kwargs: { iso_image: nil }) do |t|
        t.edit(vps, iso_image_id: nil)
        next if included?

        t.just_create(vps.log(:detach_iso_image, { id: vps.iso_image.id, name: vps.iso_image.name }))
      end

      nil
    end
  end
end
